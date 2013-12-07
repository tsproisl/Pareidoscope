#!/usr/bin/python
# -*- coding: utf-8 -*-

import operator


def get_candidates(c, nx_graph):
    """Get candidate tokens for each vertice in the graph from the
    database.
    
    Arguments:
    - `c`: Database cursor
    - `nx_graph`:

    """
    mapping = {v: i for i, v in enumerate(sorted(nx_graph.nodes()))}
    # candidates = [[] for i in range(nx_graph.number_of_nodes())]
    queries = [_create_sql_query(nx_graph, v) for v in mapping]
    queries.sort(key=lambda x: len(x[0]), reverse=True)
    for query, args in queries:
        # get sentids and positions
        # intersect sentids
        pass


def _create_sql_query(nx_graph, v):
    """Create an SQL query for the given node and return a tuple
    consisting of query string and parameters.
    
    Arguments:
    - `nx_graph`:
    - `v`:

    """
    # Deal with negation
    for key, value in nx_graph.node[v].iteritems():
        pass
