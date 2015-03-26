#!/usr/bin/python
# -*- coding: utf-8 -*-

import copy
import itertools

import networkx

from pareidoscope.utils import nx_graph


def get_subgraphs_nx(query_graph, target_graph, vertice_candidates=None):
    """Return a list of subgraphs of target_graph that are isomorphic
    to query_graph
    
    Arguments:
    - `query_graph`:
    - `target_graph`:
    - `vertice_candidates`:
    """
    bfo_graph, bfo_to_raw = get_bfo(target_graph)
    if vertice_candidates is None:
        vertice_candidates = nx_graph.get_vertice_candidates(query_graph, bfo_graph)
    vertice_candidates = reduce(lambda x, y: x.union(y), vertice_candidates)
    for subgraph in enumerate_connected_subgraphs(bfo_graph, bfo_to_raw, query_graph.number_of_nodes(), query_graph.number_of_edges(), vertice_candidates):
        vc = nx_graph.get_vertice_candidates(query_graph, subgraph)
        if match_yes_no(query_graph, subgraph, vc, 0):
            yield subgraph    


def get_subgraphs(query_graph, target_graph):
    """Return a list of subgraphs of target_graph that are isomorphic
    to query_graph
    
    Arguments:
    - `query_graph`: query graph as adjacency matrix
    - `target_graph`: target graph as adjacency matrix
    """
    query_graph = nx_graph.create_nx_digraph(query_graph)
    target_graph = nx_graph.create_nx_digraph(target_graph)
    return get_subgraphs_nx(query_graph, target_graph)


def subsumes(query_graph, target_graph):
    """Return whether the query_graph subsumes the target graph.
    
    Arguments:
    - `query_graph`:
    - `target_graph`:
    """
    qg = nx_graph.create_nx_digraph(query_graph)
    tg = nx_graph.create_nx_digraph(target_graph)
    return subsumes_nx(qg, tg)


def subsumes_nx(query_graph, target_graph, vertice_candidates=None):
    """Return whether the query_graph subsumes the target graph.
    
    Arguments:
    - `query_graph`:
    - `target_graph`:
    """
    qg = query_graph
    tg = target_graph
    if qg.number_of_nodes() > tg.number_of_nodes():
        return False
    if qg.number_of_edges() > tg.number_of_edges():
        return False
    if vertice_candidates is None:
        vertice_candidates = nx_graph.get_vertice_candidates(qg, tg)
    return match_yes_no(qg, tg, vertice_candidates, 0)


def get_choke_point_matches(query_graph, target_graph, choke_point, vertice_candidates=None):
    """Return the vertices from target that match the choke point vertice
    from query.
    
    Arguments:
        query_graph:
        target_graph:
        choke_point:
    
    Returns:
        Vertices from target_graph that correspond to the choke point
        vertice from query_graph.

    """
    if vertice_candidates is None:
        vertice_candidates = nx_graph.get_vertice_candidates(query_graph, target_graph)
    for choke_point_candidate in vertice_candidates[choke_point]:
        local_candidates = copy.deepcopy(vertice_candidates)
        local_candidates[choke_point] = set([choke_point_candidate])
        if subsumes_nx(query_graph, target_graph, local_candidates):
            yield choke_point_candidate


def choke_point_subsumes_nx(query_graph, target_graph, choke_point, choke_point_candidate, vertice_candidates=None):
    """Return whether the query_graph subsumes the target graph.

    """
    qg = query_graph
    tg = target_graph
    if qg.number_of_nodes() > tg.number_of_nodes():
        return False
    if qg.number_of_edges() > tg.number_of_edges():
        return False
    if vertice_candidates is None:
        vertice_candidates = nx_graph.get_vertice_candidates(qg, tg)
    vertice_candidates[choke_point] = vertice_candidates[choke_point].intersection(set([choke_point_candidate]))
    return match_yes_no(qg, tg, vertice_candidates, 0)


def get_bfo(target_graph, fragment=False):
    """Return target_graph in breadth-first-order as well as a mapping of
    vertices.
    
    Arguments:
    - `target_graph`:
    - `fragment`: is target graph a fragment?
    
    Raises:
    - IndexError: No root vertice has been found
    """
    graph = networkx.DiGraph()
    roots = [v[0] for v in target_graph.nodes(data=True) if "root" in v[1]]
    if len(roots) == 0 and fragment:
        all_vertices = set(target_graph.nodes())
        roots = [v for v in target_graph.nodes() if all([networkx.has_path(target_graph, v, u) for u in all_vertices - set([v])])]
    root = roots[0]
    raw_to_bfo = {root: 0}
    bfo_to_raw = {0: root}
    graph.add_node(0, target_graph.node[root])
    agenda = [root]
    seen_vertices = set([])
    vertice_counter = 1
    while len(agenda) > 0:
        vertice = agenda.pop(0)
        if vertice in seen_vertices:
            continue
        seen_vertices.add(vertice)
        edges = target_graph.out_edges(nbunch = [vertice], data = True)
        edges.sort(key = lambda x: (x[2]["relation"], x[1]))
        for source, target, label in edges:
            if target not in raw_to_bfo:
                raw_to_bfo[target] = vertice_counter
                bfo_to_raw[vertice_counter] = target
                agenda.append(target)
                vertice_counter += 1
            graph.add_node(raw_to_bfo[target], target_graph.node[target])
            graph.add_edge(raw_to_bfo[vertice], raw_to_bfo[target], label)
    return graph, bfo_to_raw


def enumerate_connected_subgraphs(graph, graph_to_raw, nr_of_vertices, nr_of_edges, vertice_candidates):
    """Python reimplementation of my implementation of the following
    algorithm
    (https://mpi-inf.mpg.de/departments/d5/teaching/ss09/queryoptimization/lecture8.pdf):
    
    EnumerateCsg(G)
    for all i ∈ [n − 1, ... , 0] descending {
        emit {v_i};
        EnumerateCsgRec(G , {v_i}, B_i );
    }
    
    EnumerateCsgRec(G, S, X)
    N = N(S) \ X;
    for all S' ⊆ N, S' = ∅, enumerate subsets first {
        emit (S ∪ S');
    }
    for all S' ⊆ N, S' = ∅, enumerate subsets first {
        EnumerateCsgRec(G, (S ∪ S'), (X ∪ N));
    }
    
    Perl implementation:
    trunk/ResourcesPareidoscope/Create/hpc_01_collect_dependency_subgraphs.pl
    
    Arguments:
    - `graph`:
    - `graph_to_raw`:
    - `min_n`:
    - `max_n`:
    """
    for vertice in sorted(graph.nodes(), reverse=True):
        max_subgraph_size = len([v for v in graph.nodes() if v >= vertice])
        if nr_of_vertices > max_subgraph_size:
            continue
        if vertice not in vertice_candidates:
            continue
        subgraph = networkx.DiGraph()
        #subgraph = [[{} for j in range(max_subgraph_size)] for i in range(max_subgraph_size)]
        subgraph.add_node(vertice, graph.node[vertice])
        nr_of_subgraph_vertices = subgraph.number_of_nodes()
        nr_of_subgraph_edges = subgraph.number_of_edges()
        if nr_of_subgraph_vertices == nr_of_vertices and nr_of_edges == nr_of_subgraph_edges:
            yield return_corpus_order(subgraph, graph_to_raw)
            continue
        prohibited_edges = set([])
        for v in [u for u in graph.nodes() if u < vertice]:
            prohibited_edges.update(set(graph.out_edges(nbunch = [v])))
            prohibited_edges.update(set(graph.in_edges(nbunch = [v])))
        # prohibit edges that do not connect to vertices from vertice_candidates
        for v in [u for u in graph.nodes() if u >= vertice]:
            prohibited_edges.update(set([e for e in graph.out_edges(nbunch = [v]) if e[1] not in vertice_candidates]))
            prohibited_edges.update(set([e for e in graph.in_edges(nbunch = [v]) if e[0] not in vertice_candidates]))
        for result in enumerate_connected_subgraphs_recursive(graph, subgraph, prohibited_edges, nr_of_vertices, nr_of_edges, graph_to_raw):
            yield result


def enumerate_connected_subgraphs_recursive(graph, subgraph, prohibited_edges, nr_of_vertices, nr_of_edges, graph_to_raw):
    """See enumerate_connected_subgraphs()
    
    Arguments:
    - `graph`:
    - `subgraph`:
    - `prohibited_edges`:
    - `nr_of_vertices`:
    - `graph_to_raw`:
    """
    out_edges, in_edges, neighbours = set([]), set([]), set([])
    neighbour_edges = {}
    subgraph_size = subgraph.number_of_nodes()
    subgraph_edges = subgraph.number_of_edges()
    for vertice in subgraph.nodes():
        for e in graph.out_edges(nbunch = [vertice]):
            if e in prohibited_edges:
                continue
            out_edges.add(e)
            neighbours.add(e[1])
            if e[1] not in neighbour_edges:
                neighbour_edges[e[1]] = []
            neighbour_edges[e[1]].append(e)
        for e in graph.in_edges(nbunch = [vertice]):
            if e in prohibited_edges:
                continue
            in_edges.add(e)
            neighbours.add(e[0])
            if e[0] not in neighbour_edges:
                neighbour_edges[e[0]] = []
            neighbour_edges[e[0]].append(e)
    # all combinations of vertices
    for combination in powerset(neighbours, 1, nr_of_vertices - subgraph_size):
        # all combinations of edges
        edges = tuple([powerset(neighbour_edges[vertice], 1, nr_of_edges - subgraph_edges) for vertice in combination])
        for edge_combi in list(itertools.product(*edges)):
            ec = []
            for edges in edge_combi:
                ec.extend(edges)
            # new vertices
            new_vertices = set([e[0] if e[0] in neighbours else e[1] for e in ec])
            if len(new_vertices) > nr_of_vertices - subgraph_size:
                continue
            # edges between new vertices
            new_edges = set([])
            for new_vertice in new_vertices:
                new_edges.update([e for e in graph.out_edges(nbunch = [new_vertice]) if e[1] in new_vertices])
            for new_edge_combi in powerset(new_edges, 0, nr_of_edges - (subgraph_edges + len(ec))):
                nec = list(new_edge_combi)
                local_subgraph = subgraph.copy()
                # add edges
                for s, t in ec + nec:
                    local_subgraph.add_edge(s, t, graph.edge[s][t])
                    for k, v in graph.node[s].iteritems():
                        local_subgraph.node[s][k] = v
                    for k, v in graph.node[t].iteritems():
                        local_subgraph.node[t][k] = v
                nr_of_subgraph_vertices = local_subgraph.number_of_nodes()
                nr_of_subgraph_edges = local_subgraph.number_of_edges()
                if nr_of_subgraph_edges != subgraph_edges + len(ec + nec):
                    raise Exception("WAAAAH")
                if nr_of_subgraph_vertices == nr_of_vertices and nr_of_edges == nr_of_subgraph_edges:
                    yield return_corpus_order(local_subgraph, graph_to_raw)
                elif nr_of_subgraph_vertices < nr_of_vertices:
                    for result in enumerate_connected_subgraphs_recursive(graph, local_subgraph, prohibited_edges.union(in_edges, out_edges, new_edges), nr_of_vertices, nr_of_edges, graph_to_raw):
                        yield result


def enumerate_csg_minmax(graph, graph_to_raw, min_vertices=2, max_vertices=5):
    """Based on
    https://mpi-inf.mpg.de/departments/d5/teaching/ss09/queryoptimization/lecture8.pdf:
    
    EnumerateCsg(G)
    for all i ∈ [n − 1, ... , 0] descending {
        emit {v_i};
        EnumerateCsgRec(G , {v_i}, B_i );
    }
    
    EnumerateCsgRec(G, S, X)
    N = N(S) \ X;
    for all S' ⊆ N, S' = ∅, enumerate subsets first {
        emit (S ∪ S');
    }
    for all S' ⊆ N, S' = ∅, enumerate subsets first {
        EnumerateCsgRec(G, (S ∪ S'), (X ∪ N));
    }
    
    Arguments:
    - `graph`:
    - `graph_to_raw`:
    - `min_vertices`:
    - `max_vertices`:
    """
    for vertice in sorted(graph.nodes(), reverse=True):
        subgraph = networkx.DiGraph()
        subgraph.add_node(vertice, graph.node[vertice])
        nr_of_subgraph_vertices = subgraph.number_of_nodes()
        if min_vertices <= nr_of_subgraph_vertices <= max_vertices:
            yield return_corpus_order(subgraph, graph_to_raw)
        prohibited_edges = set([])
        for v in [u for u in graph.nodes() if u < vertice]:
            prohibited_edges.update(set(graph.out_edges(nbunch=[v])))
            prohibited_edges.update(set(graph.in_edges(nbunch=[v])))
        for result in enumerate_csg_minmax_recursive(graph, subgraph, prohibited_edges, graph_to_raw, min_vertices, max_vertices):
            yield result


def enumerate_csg_minmax_recursive(graph, subgraph, prohibited_edges, graph_to_raw, min_vertices, max_vertices):
    """See enumerate_connected_subgraphs()
    
    Arguments:
    - `graph`:
    - `subgraph`:
    - `prohibited_edges`:
    - `graph_to_raw`:
    - `min_vertices`:
    - `max_vertices`:
    """
    out_edges, in_edges, neighbours = set([]), set([]), set([])
    neighbour_edges = {}
    subgraph_size = subgraph.number_of_nodes()
    subgraph_edges = subgraph.number_of_edges()
    for vertice in subgraph.nodes():
        for e in graph.out_edges(nbunch = [vertice]):
            if e in prohibited_edges:
                continue
            out_edges.add(e)
            neighbours.add(e[1])
            if e[1] not in neighbour_edges:
                neighbour_edges[e[1]] = []
            neighbour_edges[e[1]].append(e)
        for e in graph.in_edges(nbunch = [vertice]):
            if e in prohibited_edges:
                continue
            in_edges.add(e)
            neighbours.add(e[0])
            if e[0] not in neighbour_edges:
                neighbour_edges[e[0]] = []
            neighbour_edges[e[0]].append(e)
    # all combinations of vertices
    for combination in powerset(neighbours, 1):
        # all combinations of edges
        edges = tuple([powerset(neighbour_edges[vertice], 1) for vertice in combination])
        for edge_combi in list(itertools.product(*edges)):
            ec = []
            for edges in edge_combi:
                ec.extend(edges)
            # new vertices
            new_vertices = set([e[0] if e[0] in neighbours else e[1] for e in ec])
            # edges between new vertices
            new_edges = set([])
            for new_vertice in new_vertices:
                new_edges.update([e for e in graph.out_edges(nbunch=[new_vertice]) if e[1] in new_vertices])
            for new_edge_combi in powerset(new_edges, 0):
                nec = list(new_edge_combi)
                local_subgraph = subgraph.copy()
                # add edges
                for s, t in ec + nec:
                    local_subgraph.add_edge(s, t, graph.edge[s][t])
                    for k, v in graph.node[s].iteritems():
                        local_subgraph.node[s][k] = v
                    for k, v in graph.node[t].iteritems():
                        local_subgraph.node[t][k] = v
                nr_of_subgraph_vertices = local_subgraph.number_of_nodes()
                nr_of_subgraph_edges = local_subgraph.number_of_edges()
                if nr_of_subgraph_edges != subgraph_edges + len(ec + nec):
                    raise Exception("WAAAAH")
                if min_vertices <= nr_of_subgraph_vertices <= max_vertices:
                    yield return_corpus_order(local_subgraph, graph_to_raw)
                if nr_of_subgraph_vertices < max_vertices:
                    for result in enumerate_csg_minmax_recursive(graph, local_subgraph, prohibited_edges.union(in_edges, out_edges, new_edges), graph_to_raw, min_vertices, max_vertices):
                        yield result


def powerset(iterable, min_size, max_size = -1):
    """(Partial) powerset of set with at most max_size elements.
    
    Arguments:
    - `set`:
    - `max_size`:
    """
    s = list(iterable)
    if max_size == -1:
        max_size = len(s)
    max_size = min(max_size, len(s))
    #return itertools.chain(itertools.combinations(s, r) for r in range(max_size + 1))
    powerset = []
    for r in range(min_size, max_size + 1):
        powerset.extend(list(itertools.combinations(s, r)))
    return powerset


def return_corpus_order(subgraph, bfo_to_raw):
    """foo
    
    Arguments:
    - `subgraph`:
    - `bfo_to_raw`:
    """
    corpus_order = networkx.DiGraph()
    corpus_order.add_nodes_from([(bfo_to_raw[v], l) for v, l in subgraph.nodes(data = True)])
    corpus_order.add_edges_from([(bfo_to_raw[s], bfo_to_raw[t], l) for s, t, l in subgraph.edges(data = True)])
    return corpus_order


def match_yes_no(query_graph, target_graph, vertice_candidates, index):
    """Return wether there is at least one subgraph isomorphism
    between query_graph and target_graph.
    
    Arguments:
    - `query_graph`:
    - `target_graph`:
    - `vertice_candidates`:
    - `index`:
    """
    if index >= query_graph.number_of_nodes():
        return True
    query_outgoing = query_graph.out_edges(nbunch = [index], data = True)
    query_incoming = query_graph.in_edges(nbunch = [index], data = True)
    for cpos in vertice_candidates[index]:
        local_candidates = [cand - set([cpos]) for cand in vertice_candidates]
        local_candidates[index] = set([cpos])
        target_outgoing = target_graph.out_edges(nbunch = [cpos], data = True)
        target_incoming = target_graph.in_edges(nbunch = [cpos], data = True)
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
        local_result = match_yes_no(query_graph, target_graph, local_candidates, index + 1)
        if local_result == True:
            return True
    return False
