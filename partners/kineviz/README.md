# Kineviz

## Visualize Memgraph data with GraphXR

[Kineviz](https://www.kineviz.com/) builds visual analytics tools that help
teams explore complex connected data. Their flagship platform,
[GraphXR](https://www.kineviz.com/graphxr), provides an intuitive,
browser-based interface for analyzing graph, geospatial, and time-series
datasets through interactive visualization.

## What GraphXR brings to Memgraph users

GraphXR enables you to visually navigate your Memgraph database, run graph
algorithms, inspect relationships, and build rich visual dashboards without
writing Cypher queries. It supports dynamic filtering, styling, clustering, and
timeline exploration, making it useful for fraud analysis, network monitoring,
cybersecurity, knowledge graphs, and more. By pairing Memgraph’s real-time
graph engine with GraphXR’s visualization environment, teams get a complete
graph analytics stack.

## How the integration works

Kineviz maintains an official integration under the
[`graphxr-lite`](https://github.com/Kineviz/graphxr-lite/tree/master/memgraph)
repository. The Memgraph connector lets GraphXR communicate directly with a
running Memgraph instance through Bolt, allowing seamless data import and
two-way exploration. With a simple Docker setup, you can run Memgraph and
GraphXR together and instantly visualize your dataset using GraphXR’s
interactive tools.

