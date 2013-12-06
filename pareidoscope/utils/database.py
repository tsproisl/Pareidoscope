#!/usr/bin/python
# -*- coding: utf-8 -*-


def get_candidates(c, nx_graph):
    """Get candidate tokens for each vertice in the graph from the
    database.
    
    Arguments:
    - `c`: Database cursor
    - `nx_graph`:

    """
    mapping = {v: i for i, v in enumerate(sorted(nx_graph.nodes()))}
    # candidates = [[] for i in range(nx_graph.number_of_nodes())]
    for i, (v, l) in enumerate(nx_graph.nodes(data=True)):
        # construct SQL query
        # get sentids and positions
        # intersect sentids
        pass
