#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json

import networkx
from networkx.readwrite import json_graph

from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism
from pareidoscope.utils import nx_graph


def _extract_stars(graph, vertex, edge_stars, skel_stars, edge_to_skel={}, include_pos=False):
    """Extract star-like subgraphs from sentence for a given center
    vertex

    Arguments:
    - `graph`:
    - `position`:

    """
    identity_mapping = {v: v for v in graph.nodes()}
    pos = graph.nodes[vertex]["pos"]
    wc = graph.nodes[vertex]["wc"]
    whole_star = graph.subgraph(set([vertex] + list(graph.predecessors(vertex)) + list(graph.successors(vertex))))
    for subgraph in subgraph_enumeration.enumerate_csg_minmax(whole_star, identity_mapping, min_vertices=2, max_vertices=whole_star.__len__()):
        # vertex must be in subgraph
        if not subgraph.has_node(vertex):
            continue
        # vertex must be center of star
        other_vertices = set(subgraph.nodes()) - set([vertex])
        if len(other_vertices) == 0:
            continue
        if not all((subgraph.has_edge(vertex, x) or subgraph.has_edge(x, vertex) for x in other_vertices)):
            continue
        length = subgraph.__len__()
        degree_sequence = " ".join([str(_) for _ in sorted([subgraph.degree[_] for _ in subgraph.nodes()], reverse=True)])
        sorted_edges = " ".join(sorted([l["relation"] for s, t, l in subgraph.edges(data=True)]))
        edge_star = nx_graph.skeletize(subgraph, only_vertices=True)
        edge_star, order = nx_graph.canonize(edge_star, order=True)
        edge_center = order.index(vertex)
        edge_t = tuple(networkx.generate_edgelist(edge_star, data=["relation"]))
        edge_string = json.dumps(list(edge_t), ensure_ascii=False, sort_keys=True)
        edge_star_key = (edge_string, edge_center, pos, wc) if include_pos else (edge_string, edge_center)
        if edge_star_key not in edge_stars:
            edge_stars[edge_star_key] = {"length": length, "degree_sequence": degree_sequence, "sorted_edges": sorted_edges, "star_freq": 1, "center_set": set([vertex])}
        else:
            edge_stars[edge_star_key]["star_freq"] += 1
            edge_stars[edge_star_key]["center_set"].add(vertex)
        skel_star = nx_graph.skeletize(subgraph)
        skel_star, order = nx_graph.canonize(skel_star, order=True)
        skel_center = order.index(vertex)
        skel_t = tuple(networkx.generate_edgelist(skel_star))
        skel_string = json.dumps(list(skel_t), ensure_ascii=False, sort_keys=True)
        if (skel_string, skel_center) not in skel_stars:
            skel_stars[(skel_string, skel_center)] = {"length": length, "degree_sequence": degree_sequence, "star_freq": 1, "center_set": set([vertex])}
        else:
            skel_stars[(skel_string, skel_center)]["star_freq"] += 1
            skel_stars[(skel_string, skel_center)]["center_set"].add(vertex)
        if (edge_string, edge_center) not in edge_to_skel:
            edge_to_skel[(edge_string, edge_center)] = set([(skel_string, skel_center)])
        else:
            edge_to_skel[(edge_string, edge_center)].add((skel_string, skel_center))
    return


def _center_sets_to_center_freqs(edge_stars, skel_stars):
    """Change center_set to center_freq in both dictionaries"""
    for e in edge_stars:
        edge_stars[e]["center_freq"] = len(edge_stars[e]["center_set"])
        edge_stars[e].pop("center_set")
    for s in skel_stars:
        skel_stars[s]["center_freq"] = len(skel_stars[s]["center_set"])
        skel_stars[s].pop("center_set")


def count_isomorphisms(query, target, query_vertex, target_vertex):
    """Count isomorphisms which map query_vertex to target_vertex"""
    candidates = nx_graph.get_vertex_candidates(query, target)
    candidates[query_vertex] = set([target_vertex])
    return len(list(subgraph_isomorphism.get_subgraph_isomorphisms_nx(query, target, candidates)))


def extract_stars_for_position(args):
    """Extract star-like subgraphs from sentence for a given position
    (token)

    Arguments:
    - `sentid`:
    - `graph`:
    - `position`:

    """
    sentid, graph, position = args
    edge_stars = {}
    skel_stars = {}
    edge_to_skel = {}
    gs = json_graph.node_link_graph(json.loads(graph))
    bfo_graph, bfo_to_raw = subgraph_enumeration.get_bfo(gs)
    raw_to_bfo = {v: k for k, v in bfo_to_raw.items()}
    vertex = raw_to_bfo[position]
    _extract_stars(bfo_graph, vertex, edge_stars, skel_stars, edge_to_skel, include_pos=False)
    _center_sets_to_center_freqs(edge_stars, skel_stars)
    return sentid, edge_stars, skel_stars, edge_to_skel


def extract_all_stars(args):
    """Extract all star-like subgraphs from sentence

    Arguments:
    - `sentid`:
    - `graph`:

    """
    sentid, graph = args
    edge_stars = {}
    skel_stars = {}
    gs = json_graph.node_link_graph(json.loads(graph))
    bfo_graph, bfo_to_raw = subgraph_enumeration.get_bfo(gs)
    for vertex in bfo_graph.nodes():
        _extract_stars(bfo_graph, vertex, edge_stars, skel_stars, include_pos=True)
    _center_sets_to_center_freqs(edge_stars, skel_stars)
    return sentid, edge_stars, skel_stars
