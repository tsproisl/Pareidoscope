#!/usr/bin/python
# -*- coding: utf-8 -*-

import operator

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


def isomorphisms(go11, gr1, gc1, gn, gs):
    """Count isomorphisms
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    """
    iso_ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    # dmatch = lambda g1, g2: nx_graph.dictionary_match(g2, g1)
    # dgm = networkx.algorithms.isomorphism.DiGraphMatcher(gs, gn, dmatch, dmatch)
    # for iso in dgm.subgraph_isomorphisms_iter():
    #     isomorphism = tuple([x[0] for x in sorted(iso.iteritems(), key=operator.itemgetter(1))])
    for isomorphism in subgraph_isomorphism.get_subgraph_isomorphisms_nx(gn, gs):
        iso_ct["n"] += 1
        if matches(go11, isomorphism, gs):
            iso_ct["o11"] += 1
        if matches(gr1, isomorphism, gs):
            iso_ct["r1"] += 1
        if matches(gc1, isomorphism, gs):
            iso_ct["c1"] += 1
    return iso_ct


def subgraphs(go11, ga, gb, gr1, gc1, gn, gs):
    """Count subgraphs
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    """
    ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    bn_large = {x: 0 for x in ["o11", "r1", "c1", "n", "a", "b", "r1+c1"]}
    bn_small = {x: 0 for x in ["o11", "n", "a", "b", "a+b"]}
    for subgraph in subgraph_enumeration.get_subgraphs_nx(gn, gs):
        ct["n"] += 1
        bn_large["n"] += 1
        bn_small["n"] += 1
        subsumed_by_o11, subsumed_by_r1, subsumed_by_c1, subsumed_by_a, subsumed_by_b = None, None, None, None, None
        # isomorphisms = list(subgraph_isomorphism.get_subgraph_isomorphisms_nx(gn, subgraph))
        # subsumed_by_o11 = any([matches(go11, iso, subgraph) for iso in isomorphisms])
        # if subsumed_by_o11:
        #     subsumed_by_r1, subsumed_by_c1, subsumed_by_a, subsumed_by_b = True, True, True, True
        # else:
        #     subsumed_by_r1 = any([matches(gr1, iso, subgraph) for iso in isomorphisms])
        #     if subsumed_by_r1:
        #         subsumed_by_a = True
        #     else:
        #         subsumed_by_a = subgraph_enumeration.subsumes_nx(ga, subgraph)
        #     subsumed_by_c1 = any([matches(gc1, iso, subgraph) for iso in isomorphisms])
        #     if subsumed_by_c1:
        #         subsumed_by_b = True
        #     else:
        #         subsumed_by_b = subgraph_enumeration.subsumes_nx(gb, subgraph)
        subsumed_by_o11 = subgraph_enumeration.subsumes_nx(go11, subgraph)
        if subsumed_by_o11:
            subsumed_by_r1, subsumed_by_c1, subsumed_by_a, subsumed_by_b = True, True, True, True
        else:
            subsumed_by_r1 = subgraph_enumeration.subsumes_nx(gr1, subgraph)
            if subsumed_by_r1:
                subsumed_by_a = True
            else:
                subsumed_by_a = subgraph_enumeration.subsumes_nx(ga, subgraph)
            subsumed_by_c1 = subgraph_enumeration.subsumes_nx(gc1, subgraph)
            if subsumed_by_c1:
                subsumed_by_b = True
            else:
                subsumed_by_b = subgraph_enumeration.subsumes_nx(gb, subgraph)
        if subsumed_by_o11:
            ct["o11"] += 1
            ct["r1"] += 1
            ct["c1"] += 1
            bn_large["o11"] += 1
            bn_large["r1"] += 1
            bn_large["c1"] += 1
            bn_large["r1+c1"] += 1
            bn_small["o11"] += 1
        if subsumed_by_r1 and subsumed_by_c1 and not subsumed_by_o11:
            ct["r1"] += 0.5
            ct["c1"] += 0.5
            bn_large["r1"] += 1
            bn_large["c1"] += 1
            bn_large["r1+c1"] += 1
        if subsumed_by_r1 and not subsumed_by_c1:
            ct["r1"] += 1
            bn_large["r1"] += 1
        if subsumed_by_c1 and not subsumed_by_r1:
            ct["c1"] += 1
            bn_large["c1"] += 1
        if subsumed_by_a:
            bn_large["a"] += 1
            bn_small["a"] += 1
        if subsumed_by_b:
            bn_large["b"] += 1
            bn_small["b"] += 1
        if subsumed_by_a and subsumed_by_b:
            bn_small["a+b"] += 1
    return ct, bn_large, bn_small


def sentences(go11, ga, gb, gr1, gc1, gn, gs):
    """Count sentences
    
    Arguments:
    - `go11`:
    - `ga`:
    - `gb`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    """
    bn_large = {x: 0 for x in ["size", "o11", "r1", "c1", "n", "a", "b", "r1+c1", "a+n", "b+n"]}
    bn_small = {x: 0 for x in ["size", "o11", "n", "a", "b", "a+b+n"]}
    subsumed_by_o11 = subgraph_enumeration.subsumes_nx(go11, gs)
    subsumed_by_r1 = subgraph_enumeration.subsumes_nx(gr1, gs)
    subsumed_by_c1 = subgraph_enumeration.subsumes_nx(gc1, gs)
    subsumed_by_n = subgraph_enumeration.subsumes_nx(gn, gs)
    subsumed_by_a = subgraph_enumeration.subsumes_nx(ga, gs)
    subsumed_by_b = subgraph_enumeration.subsumes_nx(gb, gs)
    bn_large["size"] += 1
    bn_small["size"] += 1
    if subsumed_by_o11:
        bn_large["o11"] += 1
        bn_small["o11"] += 1
    if subsumed_by_a:
        bn_large["a"] += 1
        bn_small["a"] += 1
    if subsumed_by_b:
        bn_large["b"] += 1
        bn_small["b"] += 1
    if subsumed_by_n:
        bn_large["n"] += 1
        bn_small["n"] += 1
    if subsumed_by_a and subsumed_by_b and subsumed_by_n:
        bn_small["a+b+n"] += 1
    if subsumed_by_a and subsumed_by_n:
        bn_large["a+n"] += 1
    if subsumed_by_b and subsumed_by_n:
        bn_large["b+n"] += 1
    if subsumed_by_r1:
        bn_large["r1"] += 1
    if subsumed_by_c1:
        bn_large["c1"] += 1
    if subsumed_by_r1 and subsumed_by_c1:
        bn_large["r1+c1"] += 1
    return bn_large, bn_small


def run_queries(args):
    """Run queries on graphs from input_queue and write output to
    output_queue.
    
    Arguments:
    - `input_queue`:
    - `output_queue`:
    - `queries`:
    """
    sentence, queries = args
    result = []
    gs = nx_graph.create_nx_digraph_from_cwb(sentence)
    for qline in queries:
        go11, ga, gb, gr1, gc1, gn = qline
        # isomorphisms
        iso_ct = isomorphisms(go11, gr1, gc1, gn, gs)
        # subgraphs (contingency table, large bayesian network,
        # small bayesian network)
        sub_ct, sub_bnl, sub_bns = subgraphs(go11, ga, gb, gr1, gc1, gn, gs)
        # sentences (large bayesian network, small bayesian
        # network)
        sent_bnl, sent_bns = sentences(go11, ga, gb, gr1, gc1, gn, gs)
        # we could also append gziped JSON strings if full data
        # structures need too much memory
        result.append({"iso_ct": iso_ct, "sub_ct": sub_ct, "sub_bnl": sub_bnl, "sub_bns": sub_bns, "sent_bnl": sent_bnl, "sent_bns": sent_bns})
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
