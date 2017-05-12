#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import functools
import json

import networkx
from networkx.readwrite import json_graph

from pareidoscope.utils import nx_graph
from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism


def read_queries(queries_file):
    """Read all queries."""
    queries = json.load(queries_file)
    for query in queries:
        yield json_graph.node_link_graph(query, directed=True, multigraph=False)


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
    inconsistent = False
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
        inconsistent = True
    elif (not subsumed_by_gc) and (not subsumed_by_ga) and (not subsumed_by_gb):
        pass
    else:
        raise Exception("Inconsistent classification.")
    return o11, r1, c1, n, inconsistent


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
    # vid_to_gn = {l["vid"]: v for v, l in gn.nodes(data=True)}
    ct = {x: 0 for x in ["o11", "r1", "c1", "n", "inconsistent"]}
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
        o11, r1, c1, n, inconsistent = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
        if inconsistent:
            ct["inconsistent"] += 1
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
    ct = {x: 0 for x in ["o11", "r1", "c1", "n", "inconsistent"]}
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
        o11, r1, c1, n, inconsistent = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
        if inconsistent:
            ct["inconsistent"] += 1
    return ct


def choke_points(gc, ga, gb, gn, gs, choke_point, candidates=None):
    """Count choke points

    Arguments:
    - `go11`:
    - `gr1`:
    - `gc1`:
    - `gn`:
    - `gs`:
    - `choke_point`:

    """
    ct = {x: 0 for x in ["o11", "r1", "c1", "n", "inconsistent"]}
    stripped_gc = strip_vid(gc)
    stripped_ga = strip_vid(ga)
    stripped_gb = strip_vid(gb)
    choke_vid = gn.node[choke_point]["vid"]
    choke_c = [v for v, l in gc.nodes(data=True) if l["vid"] == choke_vid][0]
    choke_a = [v for v, l in ga.nodes(data=True) if l["vid"] == choke_vid][0]
    choke_b = [v for v, l in gb.nodes(data=True) if l["vid"] == choke_vid][0]
    normal_cand_c, normal_cand_a, normal_cand_b = None, None, None
    for choke_point_vertex in subgraph_enumeration.get_choke_point_matches(strip_vid(gn), gs, choke_point, vertex_candidates=candidates):
        if normal_cand_c is None:
            normal_cand_c = nx_graph.get_vertex_candidates(stripped_gc, gs)
        if normal_cand_a is None:
            normal_cand_a = nx_graph.get_vertex_candidates(stripped_ga, gs)
        if normal_cand_b is None:
            normal_cand_b = nx_graph.get_vertex_candidates(stripped_gb, gs)
        args_c = {"query_graph": stripped_gc, "choke_point": choke_c, "vertex_candidates": normal_cand_c}
        args_a = {"query_graph": stripped_ga, "choke_point": choke_a, "vertex_candidates": normal_cand_a}
        args_b = {"query_graph": stripped_gb, "choke_point": choke_b, "vertex_candidates": normal_cand_b}
        o11, r1, c1, n, inconsistent = _frequency_signature(functools.partial(subgraph_enumeration.choke_point_subsumes_nx, target_graph=gs, choke_point_candidate=choke_point_vertex), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
        if inconsistent:
            ct["inconsistent"] += 1
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
    ct = {x: 0 for x in ["o11", "r1", "c1", "n", "inconsistent"]}
    subsumed_by_n = subgraph_enumeration.subsumes_nx(strip_vid(gn), gs, vertex_candidates=candidates)
    if subsumed_by_n:
        args_c = {"query_graph": strip_vid(gc)}
        args_a = {"query_graph": strip_vid(ga)}
        args_b = {"query_graph": strip_vid(gb)}
        o11, r1, c1, n, inconsistent = _frequency_signature(functools.partial(subgraph_enumeration.subsumes_nx, target_graph=gs), args_c, args_a, args_b)
        ct["o11"] += o11
        ct["r1"] += r1
        ct["c1"] += c1
        ct["n"] += n
        if inconsistent:
            ct["inconsistent"] += 1
    return ct


def run_queries(args):
    """Run all queries on a single sentence.

    Arguments:
    - `args`:

    """
    sentence, input_format, queries, all_counting_methods = args
    result = []
    if input_format == "cwb":
        gs = nx_graph.create_nx_digraph_from_cwb(sentence)
    elif input_format == "conllu":
        gs = nx_graph.create_nx_digraph_from_conllu(sentence)
    sensible = nx_graph.is_sensible_graph(gs)
    if sensible:
        for qline in queries:
            gc, ga, gb, gn, choke_point = qline
            candidates = nx_graph.get_vertex_candidates(strip_vid(gn), gs)
            result.append(_run_query(gc, ga, gb, gn, gs, choke_point, candidates, all_counting_methods))
    return result, sensible


def run_queries_db(args):
    """Run a query on a single sentence from the database.

    Arguments:
    - `args`:

    """
    gc, ga, gb, gn, choke_point, sentence, all_counting_methods = args
    gs = json_graph.node_link_graph(json.loads(sentence))
    candidates = nx_graph.get_vertex_candidates(strip_vid(gn), gs)
    return _run_query(gc, ga, gb, gn, gs, choke_point, candidates, all_counting_methods)


def _run_query(gc, ga, gb, gn, gs, choke_point, candidates, all_counting_methods=True):
    """Run a single query on a single graph"""
    result = {}
    # choke_points (contingency table)
    choke_point_ct = {}
    if choke_point is not None:
        choke_point_ct = choke_points(gc, ga, gb, gn, gs, choke_point, candidates)
        result["choke_points"] = choke_point_ct
    if all_counting_methods:
        # isomorphisms
        iso_ct = isomorphisms(gc, ga, gb, gn, gs, candidates)
        result["isomorphisms"] = iso_ct
        # subgraphs (contingency table)
        sub_ct = subgraphs(gc, ga, gb, gn, gs, candidates)
        result["subgraphs"] = sub_ct
        # sentences (contingency table)
        sent_ct = sentences(gc, ga, gb, gn, gs, candidates)
        result["sentences"] = sent_ct
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
