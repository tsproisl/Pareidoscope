#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pareidoscope.utils import nx_graph
from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism

def get_frequencies(args):
    """Determine various frequencies (isomorphisms, subgraphs, graphs) for
    the query structures.
    
    Arguments:
        args: Contains the arguments
    
    Returns:
        If a sentence is sensible: Number of matching isomorphisms,
        subgraphs and graphs.

    """
    s, query, root = args
    sentence, sid = s
    result = {}
    gs = nx_graph.create_nx_digraph_from_cwb(sentence)
    sensible = nx_graph.is_sensible_graph(gs)
    candidates = None
    if sensible:
        isomorphisms, subgraphs, roots, graphs = 0, 0, 0, 0
        if subgraph_enumeration.subsumes_nx(query, gs, vertex_candidates=candidates):
            graphs = 1
            isomorphisms = sum(1 for _ in subgraph_isomorphism.get_subgraph_isomorphisms_nx(query, gs, vertex_candidates=candidates))
            subgraphs = sum(1 for _ in subgraph_enumeration.get_subgraphs_nx(query, gs, vertex_candidates=candidates))
            if root is not None:
                roots = sum(1 for _ in subgraph_enumeration.get_root_matches(query, gs, root))
        result = {"isomorphisms": isomorphisms, "subgraphs": subgraphs, "roots": roots, "graphs": graphs}
    return sid, result, sensible


def merge_result(result, results):
    """Merge result with results
    
    Arguments:
    - `result`:
    - `results`:
    """
    for k in result:
        if k not in results:
            results[k] = 0
        results[k] += result[k]


def merge_nested_result(result, results):
    """Merge result with results
    
    Arguments:
    - `result`:
    - `results`:
    """
    for outer_key in result:
        if outer_key not in results:
            results[outer_key] = {}
        for inner_key, value in result[outer_key].items():
            if inner_key not in results[outer_key]:
                results[outer_key][inner_key] = 0
            results[outer_key][inner_key] += value
