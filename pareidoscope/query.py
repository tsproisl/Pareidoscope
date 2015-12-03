#!/usr/bin/python
# -*- coding: utf-8 -*-

import copy
import json
import operator

import networkx
from networkx.readwrite import json_graph

from pareidoscope.utils import nx_graph
from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism


def sanity_check_c_a_b(gc, ga, gb):
    """Do a few sanity checks on the query graphs."""
    # ga should subsume gc
    ga_subsumes_gc = subgraph_enumeration.subsumes_nx(ga, gc)
    # gb should subsume gc
    gb_subsumes_gc = subgraph_enumeration.subsumes_nx(gb, gc)
    sane = ga_subsumes_gc and gb_subsumes_gc
    if not sane:
        raise Exception("G_A subsumes G_C: %s, G_B subsumes G_C: %s" % (repr(ga_subsumes_gc), repr(gb_subsumes_gc)))
    return sane


def get_n_from_c_a_b(gc, ga, gb):
    """Derive gn from gc, ga and gb and return it."""
    vid_to_ga = {l["vid"]: v for v, l in ga.nodes(data=True)}
    vid_to_gb = {l["vid"]: v for v, l in gb.nodes(data=True)}
    vid_to_gcn = {l["vid"]: v for v, l in gc.nodes(data=True)}
    # vn is the intersection of ga and gb
    vn = set(vid_to_ga.keys()) & set(vid_to_gb.keys())
    gn = networkx.DiGraph()
    for vertex, label in gc.nodes(data=True):
        vid = label["vid"]
        if vid not in vn:
            continue
        # the label is the maximum of the labels in ga and gb
        label_keys = set(ga.node[vid_to_ga[vid]].keys()) & set(gb.node[vid_to_gb[vid]].keys())
        if all([ga.node[vid_to_ga[vid]][lk] == gb.node[vid_to_gb[vid]][lk] for lk in label_keys]):
            gn.add_node(vertex, {lk: ga.node[vid_to_ga[vid]][lk] for lk in label_keys})
        else:
            raise Exception("Incompatible vertex labels: %s and  %s" % (repr(ga.node[vid_to_ga[vid]]), repr(gb.node[vid_to_gb[vid]])))
    # en is the intersection of ea and eb
    ea = set([(ga.node[s]["vid"], ga.node[t]["vid"]) for s, t in ga.edges()])
    eb = set([(gb.node[s]["vid"], gb.node[t]["vid"]) for s, t in gb.edges()])
    en = ea & eb
    for s, t in en:
        label_keys = set(ga.edge[vid_to_ga[s]][vid_to_ga[t]].keys()) & set(gb.edge[vid_to_gb[s]][vid_to_gb[t]].keys())
        if all([ga.edge[vid_to_ga[s]][vid_to_ga[t]][lk] == gb.edge[vid_to_gb[s]][vid_to_gb[t]][lk] for lk in label_keys]):
            gn.add_edge(vid_to_gcn[s], vid_to_gcn[t], {lk: ga.edge[vid_to_ga[s]][vid_to_ga[t]][lk] for lk in label_keys})
        else:
            raise Exception("Incompatible edge labels: %s and  %s" % (repr(ga.edge[vid_to_ga[s]][vid_to_ga[t]]), repr(gb.edge[vid_to_gb[s]][vid_to_gb[t]])))
    return gn


def matches(query_graph, isomorphism, target_graph):
    """Does query_graph match the isomorphism subgraph of
    target_graph?
    
    Arguments:
    - `query_graph`:
    - `isomorphism`:
    - `target_graph`:
    """
    vertex_match = all([nx_graph.dictionary_match(query_graph.node[v], target_graph.node[isomorphism[v]]) for v in query_graph.nodes()])
    edge_match = all([nx_graph.dictionary_match(query_graph.edge[s][t], target_graph.edge[isomorphism[s]][isomorphism[t]]) for s, t in query_graph.edges()])
    return vertex_match and edge_match


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
    for isomorphism in subgraph_isomorphism.get_subgraph_isomorphisms_nx(gn, gs, vertex_candidates=candidates):
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
    for subgraph in subgraph_enumeration.get_subgraphs_nx(gn, gs, vertex_candidates=candidates):
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


def choke_points(go11, gr1, gc1, gn, gs, choke_point):
    """Count choke points
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `choke_point`:

    """
    ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    for choke_point_vertex in subgraph_enumeration.get_choke_point_matches(gn, gs, choke_point):
        ct["n"] += 1
        subsumed_by_o11, subsumed_by_r1, subsumed_by_c1 = None, None, None
        subsumed_by_o11 = subgraph_enumeration.choke_point_subsumes_nx(go11, gs, choke_point, choke_point_vertex)
        if subsumed_by_o11:
            subsumed_by_r1, subsumed_by_c1 = True, True
        else:
            subsumed_by_r1 = subgraph_enumeration.choke_point_subsumes_nx(gr1, gs, choke_point, choke_point_vertex)
            subsumed_by_c1 = subgraph_enumeration.choke_point_subsumes_nx(gc1, gs, choke_point, choke_point_vertex)
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
    subsumed_by_n = subgraph_enumeration.subsumes_nx(gn, gs, vertex_candidates=candidates)
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
            gc, ga, gb, gn, choke_point = qline
            # isomorphisms
            iso_ct = isomorphisms(gc, ga, gb, gn, gs)
            # subgraphs (contingency table)
            sub_ct = subgraphs(gc, ga, gb, gn, gs)
            # choke_points (contingency table)
            choke_point_ct = {}
            if choke_point is not None:
                choke_point_ct = choke_points(gc, ga, gb, gn, gs, choke_point)
            # sentences (contingency table)
            sent_ct = sentences(gc, ga, gb, gn, gs)
            # we could also append gziped JSON strings if full data
            # structures need too much memory
            result.append({"iso_ct": iso_ct, "sub_ct": sub_ct, "choke_point_ct": choke_point_ct, "sent_ct": sent_ct})
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
