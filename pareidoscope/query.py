#!/usr/bin/python
# -*- coding: utf-8 -*-

import json
import operator

from networkx.readwrite import json_graph

from pareidoscope.utils import nx_graph
from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism


def matches(query_graph, isomorphism, target_graph):
    """Does query_graph match the isomorphism subgraph of
    target_graph?
    
    Arguments:
    - `query_graph`:
    - `isomorphism`:
    - `target_graph`:
    """
    vertice_match = all([nx_graph.dictionary_match(query_graph.node[v], target_graph.node[isomorphism[v]]) for v in query_graph.nodes()])
    edge_match = all([nx_graph.dictionary_match(query_graph.edge[s][t], target_graph.edge[isomorphism[s]][isomorphism[t]]) for s, t in query_graph.edges()])
    return vertice_match and edge_match


def isomorphisms(go11, gr1, gc1, gn, gs, candidates=None):
    """Count isomorphisms
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `candidates`:

    """
    iso_ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    # dmatch = lambda g1, g2: nx_graph.dictionary_match(g2, g1)
    # dgm = networkx.algorithms.isomorphism.DiGraphMatcher(gs, gn, dmatch, dmatch)
    # for iso in dgm.subgraph_isomorphisms_iter():
    #     isomorphism = tuple([x[0] for x in sorted(iso.iteritems(), key=operator.itemgetter(1))])
    for isomorphism in subgraph_isomorphism.get_subgraph_isomorphisms_nx(gn, gs, vertice_candidates=candidates):
        iso_ct["n"] += 1
        if matches(go11, isomorphism, gs):
            iso_ct["o11"] += 1
        if matches(gr1, isomorphism, gs):
            iso_ct["r1"] += 1
        if matches(gc1, isomorphism, gs):
            iso_ct["c1"] += 1
    return iso_ct


def subgraphs(go11, gr1, gc1, gn, gs, candidates=None):
    """Count subgraphs
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `candidates`:

    """
    ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    for subgraph in subgraph_enumeration.get_subgraphs_nx(gn, gs, vertice_candidates=candidates):
        ct["n"] += 1
        subsumed_by_o11, subsumed_by_r1, subsumed_by_c1 = None, None, None
        subsumed_by_o11 = subgraph_enumeration.subsumes_nx(go11, subgraph)
        if subsumed_by_o11:
            subsumed_by_r1, subsumed_by_c1 = True, True
        else:
            subsumed_by_r1 = subgraph_enumeration.subsumes_nx(gr1, subgraph)
            subsumed_by_c1 = subgraph_enumeration.subsumes_nx(gc1, subgraph)
        if subsumed_by_o11:
            ct["o11"] += 1
            ct["r1"] += 1
            ct["c1"] += 1
        if subsumed_by_r1 and subsumed_by_c1 and not subsumed_by_o11:
            ct["r1"] += 0.5
            ct["c1"] += 0.5
        if subsumed_by_r1 and not subsumed_by_c1:
            ct["r1"] += 1
        if subsumed_by_c1 and not subsumed_by_r1:
            ct["c1"] += 1
    return ct


def sentences(go11, gr1, gc1, gn, gs, candidates=None):
    """Count sentences
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `candidates`:

    """
    ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    subsumed_by_o11, subsumed_by_r1, subsumed_by_c1, subsumed_by_n = None, None, None, None
    subsumed_by_n = subgraph_enumeration.subsumes_nx(gn, gs, vertice_candidates=candidates)
    if subsumed_by_n:
        subsumed_by_o11 = subgraph_enumeration.subsumes_nx(go11, gs)
        if subsumed_by_o11:
            subsumed_by_r1, subsumed_by_c1 = True, True
        else:
            subsumed_by_r1 = subgraph_enumeration.subsumes_nx(gr1, gs)
            subsumed_by_c1 = subgraph_enumeration.subsumes_nx(gc1, gs)
    else:
        subsumed_by_o11, subsumed_by_r1, subsumed_by_c1 = False, False, False
    if subsumed_by_n:
        ct["n"] += 1
    if subsumed_by_o11:
        ct["o11"] += 1
        ct["r1"] += 1
        ct["c1"] += 1
    if subsumed_by_r1 and subsumed_by_c1 and not subsumed_by_o11:
        ct["r1"] += 0.5
        ct["c1"] += 0.5
    if subsumed_by_r1 and not subsumed_by_c1:
        ct["r1"] += 1
    if subsumed_by_c1 and not subsumed_by_r1:
        ct["c1"] += 1
    return ct


def run_queries(args):
    """Run queries on graphs from input_queue and write output to
    output_queue.
    
    Arguments:
    - `args`:
    """
    sentence, queries = args
    result = []
    gs = nx_graph.create_nx_digraph_from_cwb(sentence)
    sensible = nx_graph.is_sensible_graph(gs)
    if sensible:
        for qline in queries:
            go11, gr1, gc1, gn = qline
            # isomorphisms
            iso_ct = isomorphisms(go11, gr1, gc1, gn, gs)
            # subgraphs (contingency table)
            sub_ct = subgraphs(go11, gr1, gc1, gn, gs)
            # sentences (contingency table)
            sent_ct = sentences(go11, gr1, gc1, gn, gs)
            # we could also append gziped JSON strings if full data
            # structures need too much memory
            result.append({"iso_ct": iso_ct, "sub_ct": sub_ct, "sent_ct": sent_ct})
    return result, sensible


def run_queries_db(args):
    """Run queries on graphs from input_queue and write output to
    output_queue.
    
    Arguments:
    - `args`:
    """
    go11, gr1, gc1, gn, sentence, candidates = args
    gs = json_graph.node_link_graph(json.loads(sentence))
    # isomorphisms
    iso_ct = isomorphisms(go11, gr1, gc1, gn, gs, candidates)
    # subgraphs (contingency table)
    sub_ct = subgraphs(go11, gr1, gc1, gn, gs, candidates)
    # sentences (contingency table)
    sent_ct = sentences(go11, gr1, gc1, gn, gs, candidates)
    # we could also append gziped JSON strings if full data
    # structures need too much memory
    result = {"iso_ct": iso_ct, "sub_ct": sub_ct, "sent_ct": sent_ct}
    return result


def merge_result(result, results):
    """Merge result with results
    
    Arguments:
    - `result`:
    - `results`:
    """
    for i, query in enumerate(result):
        for method in query:
            if method not in results[i]:
                results[i][method] = {}
            for frequency in query[method]:
                results[i][method][frequency] = results[i][method].get(frequency, 0) + query[method][frequency]


def merge_result_db(result, query_number, results):
    """Merge result with results
    
    Arguments:
    - `query`:
    - `query_number`:
    - `results`:
    """
    for method in result:
        if method not in results[query_number]:
            results[query_number][method] = {}
        for frequency in result[method]:
            results[query_number][method][frequency] = results[query_number][method].get(frequency, 0) + result[method][frequency]
