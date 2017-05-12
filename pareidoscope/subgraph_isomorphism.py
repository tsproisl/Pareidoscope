#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pareidoscope.utils import nx_graph


def get_subgraph_isomorphisms_nx(query_graph, target_graph, vertex_candidates=None):
    """Return a list of isomorphisms that map vertices and edges from
    query_graph to vertices and edges from target_graph.

    """
    subgraph_isomorphisms = None
    if vertex_candidates is None:
        vertex_candidates = nx_graph.get_vertex_candidates(query_graph, target_graph)
    if any([len(vc) == 0 for vc in vertex_candidates]):
        return iter(())
    if nx_graph.is_purely_structural(query_graph):
        subgraph_isomorphisms = match_structural(query_graph, target_graph, vertex_candidates, 0)
    else:
        subgraph_isomorphisms = match(query_graph, target_graph, vertex_candidates, 0)
    return subgraph_isomorphisms


def get_subgraph_isomorphisms(query_graph, target_graph):
    """Return a list of isomorphisms that map vertices and edges from
    query_graph to vertices and edges from target_graph.

    Arguments:
    - `query_graph`: query graph as adjacency matrix
    - `target_graph`: target graph as adjacency matrix
    """
    query_graph = nx_graph.create_nx_digraph(query_graph)
    target_graph = nx_graph.create_nx_digraph(target_graph)
    return get_subgraph_isomorphisms_nx(query_graph, target_graph)


def match(query_graph, target_graph, vertex_candidates, index):
    """Find isomorphisms between query_graph and target_graph.

    The implementation follows Proisl/Uhrig (2012: 2753) quite
    closely.

    """
    if index >= query_graph.number_of_nodes():
        yield tuple([next(iter(cand)) for cand in vertex_candidates])
    else:
        query_outgoing = query_graph.out_edges(nbunch=[index], data=True)
        query_incoming = query_graph.in_edges(nbunch=[index], data=True)
        for cpos in vertex_candidates[index]:
            local_candidates = [cand - set([cpos]) for cand in vertex_candidates]
            local_candidates[index] = set([cpos])
            target_outgoing = target_graph.out_edges(nbunch=[cpos], data=True)
            target_incoming = target_graph.in_edges(nbunch=[cpos], data=True)
            target_candidates = [set([]) for _ in query_graph.nodes()]
            for qs, qt, ql in query_outgoing:
                for ts, tt, tl in target_outgoing:
                    if nx_graph.dictionary_match(ql, tl):
                        target_candidates[qt] = target_candidates[qt].union(set([tt]))
            for qs, qt, ql in query_incoming:
                for ts, tt, tl in target_incoming:
                    if nx_graph.dictionary_match(ql, tl):
                        target_candidates[qs] = target_candidates[qs].union(set([ts]))
            for idx in range(query_graph.number_of_nodes()):
                if len(target_candidates[idx]) > 0:
                    local_candidates[idx] = local_candidates[idx].intersection(target_candidates[idx])
            if any([len(x) == 0 for x in local_candidates]):
                continue
            for result in match(query_graph, target_graph, local_candidates, index + 1):
                yield result


def match_structural(query_graph, target_graph, vertex_candidates, index):
    """Find isomorphisms between query_graph and target_graph.

    The implementation follows Proisl/Uhrig (2012: 2753) quite
    closely.

    """
    if index >= query_graph.number_of_nodes():
        yield tuple([next(iter(cand)) for cand in vertex_candidates])
    else:
        query_outgoing = query_graph.out_edges(nbunch=[index], data=True)
        query_incoming = query_graph.in_edges(nbunch=[index], data=True)
        for cpos in vertex_candidates[index]:
            local_candidates = [cand - set([cpos]) for cand in vertex_candidates]
            local_candidates[index] = set([cpos])
            target_outgoing = target_graph.out_edges(nbunch=[cpos], data=True)
            target_incoming = target_graph.in_edges(nbunch=[cpos], data=True)
            target_candidates = [set([]) for _ in query_graph.nodes()]
            tout_indexes = set([t for s, t, l in target_outgoing])
            tin_indexes = set([s for s, t, l in target_incoming])
            for s, t, l in query_outgoing:
                target_candidates[t] = target_candidates[t].union(tout_indexes)
            for s, t, l in query_incoming:
                target_candidates[s] = target_candidates[s].union(tin_indexes)
            for idx in range(query_graph.number_of_nodes()):
                if len(target_candidates[idx]) > 0:
                    local_candidates[idx] = local_candidates[idx].intersection(target_candidates[idx])
            if any([len(x) == 0 for x in local_candidates]):
                continue
            for result in match_structural(query_graph, target_graph, local_candidates, index + 1):
                yield result


if __name__ == "__main__":
    query_graph = [[{"word": "bachelor"}, {"relation": "amod"}], [{}, {}]]
    target_graph = [[{"word": "he"}, {}, {}, {}, {}, {}], [{}, {"word": "was"}, {}, {}, {}, {}], [{}, {}, {"word": "an"}, {}, {}, {}], [{}, {}, {}, {"word": "old"}, {}, {}], [{}, {}, {}, {}, {"word": "confirmed"}, {}], [{"relation": "nsubj"}, {"relation": "cop"}, {"relation": "det"}, {"relation": "amod"}, {"relation": "amod"}, {"word": "bachelor"}]]
    print(list(get_subgraph_isomorphisms(query_graph, target_graph)))
    query_graph = [[{}, {'relation': '.+'}, {'relation': '.+'}], [{}, {}, {}], [{}, {}, {}]]
    target_graph = [[{'root': 'root', 'word': 'v0989'}, {'relation': 'e00'}, {}, {}, {}, {}], [{}, {'word': 'v2248'}, {'relation': 'e29'}, {}, {'relation': 'e04'}, {}], [{}, {}, {'word': 'v5171'}, {'relation': 'e05'}, {}, {}], [{}, {}, {}, {'word': 'v7172'}, {}, {}], [{}, {}, {}, {}, {'word': 'v6658'}, {'relation': 'e20'}], [{}, {}, {}, {}, {}, {'word': 'v9605'}]]
    print(list(get_subgraph_isomorphisms(query_graph, target_graph)))
