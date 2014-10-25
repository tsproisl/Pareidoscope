#!/usr/bin/python
# -*- coding: utf-8 -*-

import collections
import json

import networkx
from networkx.readwrite import json_graph

from pareidoscope import subgraph_enumeration
from pareidoscope import subgraph_isomorphism
from pareidoscope.utils import nx_graph


def _extract_stars(graph, vertice, edge_stars, skel_stars, edge_to_skel={}):
    """Extract star-like subgraphs from sentence for a given center
    vertice

    Arguments:
    - `graph`:
    - `position`:

    """
    identity_mapping = {v: v for v in graph.nodes()}
    whole_star = graph.subgraph(set([vertice] + graph.predecessors(vertice) + graph.successors(vertice)))
    for subgraph in subgraph_enumeration.enumerate_csg_minmax(whole_star, identity_mapping, min_vertices=2, max_vertices=whole_star.__len__()):
        # vertice must be in subgraph
        if not subgraph.has_node(vertice):
            continue
        # vertice must be center of star
        other_vertices = set(subgraph.nodes()) - set([vertice])
        if len(other_vertices) == 0:
            continue
        if not all((subgraph.has_edge(vertice, x) or subgraph.has_edge(x, vertice) for x in other_vertices)):
            continue
        length = subgraph.__len__()
        degree_sequence = " ".join([str(_) for _ in sorted([subgraph.degree(_) for _ in subgraph.nodes()], reverse=True)])
        sorted_edges = " ".join(sorted([l["relation"] for s, t, l in subgraph.edges(data=True)]))
        edge_star = subgraph.copy()
        nx_graph.skeletize_inplace(edge_star, only_vertices=True)
        edge_star, order = nx_graph.canonize(edge_star, order=True)
        edge_center = order.index(vertice)
        edge_t = tuple(networkx.generate_edgelist(edge_star, data=["relation"]))
        edge_string = json.dumps(list(edge_t), ensure_ascii=False)
        if (edge_string, edge_center) not in edge_stars:
            edge_stars[(edge_string, edge_center)] = {"length": length, "degree_sequence": degree_sequence, "sorted_edges": sorted_edges, "star_freq": 1, "center_set": set([vertice])}
        else:
            edge_stars[(edge_string, edge_center)]["star_freq"] += 1
            edge_stars[(edge_string, edge_center)]["center_set"].add(vertice)
        skel_star = subgraph.copy()
        nx_graph.skeletize_inplace(skel_star)
        skel_star, order = nx_graph.canonize(skel_star, order=True)
        skel_center = order.index(vertice)
        skel_t = tuple(networkx.generate_edgelist(skel_star))
        skel_string = json.dumps(list(skel_t), ensure_ascii=False)
        if (skel_string, skel_center) not in skel_stars:
            skel_stars[(skel_string, skel_center)] = {"length": length, "degree_sequence": degree_sequence, "star_freq": 1, "center_set": set([vertice])}
        else:
            skel_stars[(skel_string, skel_center)]["star_freq"] += 1
            skel_stars[(skel_string, skel_center)]["center_set"].add(vertice)
        if (edge_string, edge_center) not in edge_to_skel:
            edge_to_skel[(edge_string, edge_center)] = set([(skel_string, skel_center)])
        else:
            edge_to_skel[(edge_string, edge_center)].add((skel_string, skel_center))
    return


def count_isomorphisms(query, target, query_vertice, target_vertice):
    """Count isomorphisms which map query_vertice to target_vertice"""
    candidates = nx_graph.get_vertice_candidates(query, target)
    candidates[query_vertice] = set([target_vertice])
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
    raw_to_bfo = {v: k for k, v in bfo_to_raw.iteritems()}
    vertice = raw_to_bfo[position]
    _extract_stars(bfo_graph, vertice, edge_stars, skel_stars, edge_to_skel)
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
    for vertice in bfo_graph.nodes():
        _extract_stars(bfo_graph, vertice, edge_stars, skel_stars)
    return sentid, edge_stars, skel_stars
