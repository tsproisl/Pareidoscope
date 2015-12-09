#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import copy
import functools
import json
import operator

import networkx
from networkx.readwrite import json_graph

from pareidoscope.utils import nx_graph
from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism


def sanity_check_c_a_b(gc, ga, gb):
    """Do a few sanity checks on the query graphs."""
    connected_c = networkx.is_weakly_connected(gc)
    connected_a = networkx.is_weakly_connected(ga)
    connected_b = networkx.is_weakly_connected(gb)
    vid_c = set([l["vid"] for v, l in gc.nodes(data=True)])
    vid_a = set([l["vid"] for v, l in ga.nodes(data=True)])
    vid_b = set([l["vid"] for v, l in gb.nodes(data=True)])
    # vids are unique
    vid_c_uniq = gc.number_of_nodes() == len(vid_c)
    vid_a_uniq = ga.number_of_nodes() == len(vid_a)
    vid_b_uniq = gb.number_of_nodes() == len(vid_b)
    # union of vid_a and vid_b is vid_c
    a_and_b_is_c = vid_a | vid_b == vid_c
    # ga should subsume gc
    ga_subsumes_gc = subgraph_enumeration.subsumes_nx(ga, gc)
    # gb should subsume gc
    gb_subsumes_gc = subgraph_enumeration.subsumes_nx(gb, gc)
    sane = all([connected_c, connected_a, connected_b, vid_c_uniq, vid_a_uniq, vid_b_uniq, a_and_b_is_c, ga_subsumes_gc, gb_subsumes_gc])
    if not sane:
        raise Exception("Incorrect formulation of query.")
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
    # make sure that the remaining vertices are consecutively labeled
    gn = nx_graph.ensure_consecutive_vertices(gn)
    if not networkx.is_weakly_connected(gn):
        raise Exception("gn is not a connected graph")
    return gn


def strip_vid(graph):
    """Return a copy of graph without vertex id (vid) labels."""
    copy = graph.copy()
    for vertex in copy.nodes():
        del copy.node[vertex]["vid"]
    return copy
    

def _get_isomorphism_vertex_candidates(query_graph, normal_candidates, v_target, v_isomorphism, vid_to_iso):
    """Return vertex candidates that are compatible with isomorphism."""
    isomorphism_candidates = [set([vid_to_iso[l["vid"]]]) if l["vid"] in vid_to_iso else v_target - v_isomorphism for v, l in sorted(query_graph.nodes(data=True))]
    candidates = [a & b for a, b in zip(normal_candidates, isomorphism_candidates)]
    return candidates


def _get_subgraph_vertex_candidates(query_graph, normal_candidates, vid_n, v_target, v_subgraph):
    """Return vertex candidates that are compatible with subgraph."""
    subgraph_candidates = [v_subgraph if l["vid"] in vid_n else v_target - v_subgraph for v, l in sorted(query_graph.nodes(data=True))]
    candidates = [a & b for a, b in zip(normal_candidates, subgraph_candidates)]
    return candidates


def _frequency_signature(subsumes, args_c, args_a, args_b):
    """Return O11, R1, C1 and N for gs."""
    subsumed_by_gc = subsumes(**args_c)
    subsumed_by_ga = subsumes(**args_a)
    subsumed_by_gb = subsumes(**args_b)
    o11, r1, c1, n = 0, 0, 0, 0
    n = 1
    if subsumed_by_gc and subsumed_by_ga and subsumed_by_gb:
        o11 = 1
        r1 = 1
        c1 = 1
    elif (not subsumed_by_gc) and subsumed_by_ga and (not subsumed_by_gb):
        r1 = 1
    elif (not subsumed_by_gc) and (not subsumed_by_ga) and subsumed_by_gb:
        c1 = 1
    elif (not subsumed_by_gc) and subsumed_by_ga and subsumed_by_gb:
        r1 = 0.5
        c1 = 0.5
    elif (not subsumed_by_gc) and (not subsumed_by_ga) and (not subsumed_by_gb):
        pass
    else:
        raise Exception("Inconsistent classification.")
    return o11, r1, c1, n


def isomorphisms(gc, ga, gb, gn, gs, candidates=None):
    """Count isomorphisms
    
    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `candidates`:

    """
    vid_to_gn = {l["vid"]: v for v, l in gn.nodes(data=True)}
    ct = {x: 0 for x in ["o11", "r1", "c1", "n"]}
    vs = set(gs.nodes())
    stripped_gc = strip_vid(gc)
    stripped_ga = strip_vid(ga)
    stripped_gb = strip_vid(gb)
    normal_cand_c, normal_cand_a, normal_cand_b = None, None, None
    for isomorphism in subgraph_isomorphism.get_subgraph_isomorphisms_nx(strip_vid(gn), gs, vertex_candidates=candidates):
        if normal_cand_c is None:
            normal_cand_c = nx_graph.get_vertex_candidates(stripped_gc, gs)
        if normal_cand_a is None:
            normal_cand_a = nx_graph.get_vertex_candidates(stripped_ga, gs)
        if normal_cand_b is None:
            normal_cand_b = nx_graph.get_vertex_candidates(stripped_gb, gs)
        vid_iso = {gn.node[qv]["vid"]: tv for qv, tv in zip(sorted(gn.nodes()), isomorphism)}
        v_isomorphism = set(isomorphism)
        vert_cand_c = _get_isomorphism_vertex_candidates(gc, normal_cand_c, vs, v_isomorphism, vid_iso)
        vert_cand_a = _get_isomorphism_vertex_candidates(ga, normal_cand_a, vs, v_isomorphism, vid_iso)
        vert_cand_b = _get_isomorphism_vertex_candidates(gb, normal_cand_b, vs, v_isomorphism, vid_iso)
        args_c = {"query_graph": stripped_gc, "vertex_candidates": vert_cand_c}
        args_a = {"query_graph": stripped_ga, "vertex_candidates": vert_cand_a}
        args_b = {"query_graph": stripped_gb, "vertex_candidates": vert_cand_b}
        o11, r1, c1, n = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
    return ct


def subgraphs(gc, ga, gb, gn, gs, candidates=None):
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
    vid_n = set([l["vid"] for v, l in gn.nodes(data=True)])
    vs = set(gs.nodes())
    stripped_gc = strip_vid(gc)
    stripped_ga = strip_vid(ga)
    stripped_gb = strip_vid(gb)
    normal_cand_c, normal_cand_a, normal_cand_b = None, None, None
    for subgraph in subgraph_enumeration.get_subgraphs_nx(strip_vid(gn), gs, vertex_candidates=candidates):
        if normal_cand_c is None:
            normal_cand_c = nx_graph.get_vertex_candidates(stripped_gc, gs)
        if normal_cand_a is None:
            normal_cand_a = nx_graph.get_vertex_candidates(stripped_ga, gs)
        if normal_cand_b is None:
            normal_cand_b = nx_graph.get_vertex_candidates(stripped_gb, gs)
        v_subgraph = set(subgraph.nodes())
        vert_cand_c = _get_subgraph_vertex_candidates(gc, normal_cand_c, vid_n, vs, v_subgraph)
        vert_cand_a = _get_subgraph_vertex_candidates(ga, normal_cand_a, vid_n, vs, v_subgraph)
        vert_cand_b = _get_subgraph_vertex_candidates(gb, normal_cand_b, vid_n, vs, v_subgraph)
        args_c = {"query_graph": stripped_gc, "vertex_candidates": vert_cand_c}
        args_a = {"query_graph": stripped_ga, "vertex_candidates": vert_cand_a}
        args_b = {"query_graph": stripped_gb, "vertex_candidates": vert_cand_b}
        o11, r1, c1, n = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
    return ct


def choke_points(gc, ga, gb, gn, gs, choke_point):
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
    stripped_gc = strip_vid(gc)
    stripped_ga = strip_vid(ga)
    stripped_gb = strip_vid(gb)
    choke_vid = gn.node[choke_point]["vid"]
    choke_c = [v for v, l in gc.nodes(data=True) if l["vid"] == choke_vid][0]
    choke_a = [v for v, l in ga.nodes(data=True) if l["vid"] == choke_vid][0]
    choke_b = [v for v, l in gb.nodes(data=True) if l["vid"] == choke_vid][0]
    normal_cand_c, normal_cand_a, normal_cand_b = None, None, None
    for choke_point_vertex in subgraph_enumeration.get_choke_point_matches(strip_vid(gn), gs, choke_point):
        if normal_cand_c is None:
            normal_cand_c = nx_graph.get_vertex_candidates(stripped_gc, gs)
        if normal_cand_a is None:
            normal_cand_a = nx_graph.get_vertex_candidates(stripped_ga, gs)
        if normal_cand_b is None:
            normal_cand_b = nx_graph.get_vertex_candidates(stripped_gb, gs)
        args_c = {"query_graph": stripped_gc, "choke_point": choke_c, "vertex_candidates": normal_cand_c}
        args_a = {"query_graph": stripped_ga, "choke_point": choke_a, "vertex_candidates": normal_cand_a}
        args_b = {"query_graph": stripped_gb, "choke_point": choke_b, "vertex_candidates": normal_cand_b}
        o11, r1, c1, n = _frequency_signature(functools.partial(subgraph_enumeration.choke_point_subsumes_nx, target_graph=gs, choke_point_candidate=choke_point_vertex), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
    return ct


def sentences(gc, ga, gb, gn, gs, candidates=None):
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
    subsumed_by_n = subgraph_enumeration.subsumes_nx(strip_vid(gn), gs, vertex_candidates=candidates)
    if subsumed_by_n:
        args_c = {"query_graph": strip_vid(gc)}
        args_a = {"query_graph": strip_vid(ga)}
        args_b = {"query_graph": strip_vid(gb)}
        o11, r1, c1, n = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs, vertex_candidates=candidates), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
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
            # result.append({"choke_point_ct": choke_point_ct})
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
