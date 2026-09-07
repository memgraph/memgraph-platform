#!/usr/bin/env python3
"""AI Memory with Memgraph: seed + recall using the real Context Graph packages.

Unlike a hand-rolled schema, this writes semantic/episodic/procedural memory
through the same libraries a live coding-assistant plugin uses:

  - sessions-graph : semantic memory  -- durable, user-owned facts (Memory nodes)
  - actions-graph   : episodic memory -- timestamped session/action history
  - skills-graph    : procedural memory -- named, reusable how-tos (Skill nodes)

See https://github.com/memgraph/ai-toolkit/tree/main/context-graph for the
full Context Graph project these packages belong to.

Connects via the same MEMGRAPH_URL / MEMGRAPH_USER / MEMGRAPH_PASSWORD /
MEMGRAPH_DATABASE env vars every package in that project reads (defaults to
bolt://localhost:7687, matching this demo's own container).
"""

import os
import sys

from actions_graph import ActionsGraph
from actions_graph.models import ActionStatus, Session
from memgraph_toolbox.api.memgraph import Memgraph
from sessions_graph import SessionsGraph
from skills_graph import Skill, SkillGraph

USER_ID = "acme-corp"  # the identity this durable memory belongs to
KICKOFF_SESSION = "session-acme-kickoff"
FOLLOWUP_SESSION = "session-acme-followup"
SKILL_NAME = "schedule-follow-up"


def _supports_color() -> bool:
    if not sys.stdout.isatty():
        return False
    if os.name != "nt":
        return True
    # Windows consoles ignore ANSI escapes until virtual-terminal processing is
    # switched on, and older ones cannot do it at all -- in which case fall back
    # to plain text instead of printing "[1;36m" at the user.
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_uint32()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        return bool(kernel32.SetConsoleMode(handle, mode.value | 0x0004))
    except Exception:
        return False


CYAN, RESET = ("\033[1;36m", "\033[0m") if _supports_color() else ("", "")


def log(msg: str) -> None:
    print(f"\n{CYAN}==> {msg}{RESET}")


def link_user_session(db: Memgraph, user_id: str, session_id: str) -> None:
    # sessions-graph is the sole owner of (:User)-[:HAD_SESSION]->(:Session);
    # this mirrors exactly what its SessionsGraphConnector does on SESSION_START.
    db.query(
        """
        MERGE (u:User {user_id: $user_id})
        MERGE (s:Session {session_id: $session_id})
        MERGE (u)-[:HAD_SESSION]->(s)
        """,
        params={"user_id": user_id, "session_id": session_id},
    )


def seed(db: Memgraph) -> None:
    actions = ActionsGraph(db)
    memories = SessionsGraph(db)
    skills = SkillGraph(db)

    actions.setup()
    memories.setup()
    skills.setup()

    # Sessions must exist before anything else references their session_id
    # (save_memory's provenance MERGE and record_skill_usage's MERGE would
    # otherwise race actions-graph's own unique constraint on Session).
    log("Episodic: what the system EXPERIENCED (two real sessions, in order)")
    actions.create_session(
        Session(
            session_id=KICKOFF_SESSION,
            started_at="2026-06-30T15:00:00+00:00",
            ended_at="2026-06-30T15:30:00+00:00",
            status=ActionStatus.COMPLETED,
        )
    )
    actions.create_session(
        Session(
            session_id=FOLLOWUP_SESSION,
            started_at="2026-07-07T15:00:00+00:00",
            ended_at="2026-07-07T15:30:00+00:00",
            status=ActionStatus.COMPLETED,
        )
    )
    link_user_session(db, USER_ID, KICKOFF_SESSION)
    link_user_session(db, USER_ID, FOLLOWUP_SESSION)

    for session_id, when in (
        (KICKOFF_SESSION, "2026-06-30T15:05:00+00:00"),
        (FOLLOWUP_SESSION, "2026-07-07T15:05:00+00:00"),
    ):
        call = actions.record_tool_call(
            session_id=session_id,
            tool_name="schedule_meeting",
            tool_input={"client": "Acme Corp", "weekday": "Tuesday", "duration_min": 30},
            tool_use_id=f"{session_id}-call",
            timestamp=when,
        )
        actions.record_tool_result(
            session_id=session_id,
            tool_use_id=call.tool_use_id,
            tool_name="schedule_meeting",
            content="booked",
            timestamp=when,
        )
    print("Wrote 2 Sessions, 4 Actions (ToolCall + ToolResult each, FOLLOWED_BY sequenced).")

    log("Semantic: what the system KNOWS")
    memories.save_memory(
        user_id=USER_ID,
        content="Acme Corp's contact is Dana Lee (timezone America/New_York); they prefer 30-minute meetings.",
        session_id=KICKOFF_SESSION,
    )
    print("Wrote 1 Memory.")

    log("Procedural: what the system KNOWS HOW TO DO")
    skills.add_skill(
        Skill(
            name=SKILL_NAME,
            description="Schedule a follow-up meeting with a client the assistant has met before.",
            content=(
                "1. Book a calendar slot matching the client's timezone and preferred meeting length.\n"
                "2. Send a calendar invite."
            ),
        )
    )
    skills.record_skill_usage(
        session_id=FOLLOWUP_SESSION,
        skill_name=SKILL_NAME,
        action="used",
        timestamp="2026-07-07T15:06:00+00:00",
    )
    print("Wrote 1 Skill, 1 USED_SKILL usage.")


def recall(db: Memgraph) -> None:
    actions = ActionsGraph(db)
    memories = SessionsGraph(db)
    skills = SkillGraph(db)

    log("Semantic recall: what do we know about the client?")
    for m in memories.get_memories(USER_ID):
        print(f"- {m.content}")

    log("Episodic recall: what happened last time? (most recent session)")
    last_session = actions.list_sessions(limit=1)[0]
    print(f"- session {last_session.session_id} started_at={last_session.started_at}")
    for a in actions.get_session_actions(last_session.session_id):
        print(f"  - {a.action_type.value} tool={getattr(a, 'tool_name', None)} at {a.timestamp}")

    log("Procedural recall: how do we schedule a follow-up?")
    skill = skills.get_skill(SKILL_NAME)
    print(skill.content)

    log("Interconnected recall: one traversal joining all three")
    # semantic (User-HAS_MEMORY->Memory) + episodic (User-HAD_SESSION->Session
    # -HAS_ACTION->Action) + procedural (Session-USED_SKILL->Skill), all through
    # the shared User/Session nodes -- see context-graph/CONTEXT-MAP.md.
    rows = db.query(
        """
        MATCH (u:User {user_id: $user_id})-[:HAS_MEMORY]->(mem:Memory)
        MATCH (u)-[:HAD_SESSION]->(s:Session)-[:HAS_ACTION]->(a:Action {tool_name: "schedule_meeting"})
        WITH u, mem, s, a ORDER BY s.started_at DESC LIMIT 1
        OPTIONAL MATCH (s)-[:USED_SKILL]->(sk:Skill)
        RETURN mem.content AS client_facts, s.session_id AS last_session,
               a.timestamp AS last_meeting_at, sk.name AS skill, sk.content AS how_to
        """,
        params={"user_id": USER_ID},
    )
    for row in rows:
        print(f"client_facts  : {row['client_facts']}")
        print(f"last_session  : {row['last_session']} (at {row['last_meeting_at']})")
        print(f"skill         : {row['skill']}")
        print(f"how_to        : {row['how_to']}")


if __name__ == "__main__":
    db = Memgraph()
    seed(db)
    recall(db)
