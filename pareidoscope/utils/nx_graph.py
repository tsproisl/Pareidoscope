#!/usr/bin/python
# -*- coding: utf-8 -*-

import itertools
import re

import networkx

def create_nx_digraph(adj_matrix):
    """Return a networkx.DiGraph object of the adjacency matrix.
    
    Arguments:
    - `adj_matrix`:
    """
    dg = networkx.DiGraph()
    dg.add_nodes_from([(i, adj_matrix[i][i]) for i in range(len(adj_matrix))])
    for i in range(len(adj_matrix)):
        for j in range(len(adj_matrix)):
            if i == j:
                continue
            if adj_matrix[i][j]:
                dg.add_edge(i, j, adj_matrix[i][j])
    return dg


def create_nx_digraph_from_cwb(cwb):
    """Return a networkx.DiGraph object of the CWB representation.
    
    Arguments:
    - `cwb`:
    """
    relpattern = re.compile(r"^(?P<relation>[^(]+)[(](?P<offset>-?\d+)(?:'*),0(?:'*)[)]$")
    dg = networkx.DiGraph()
    attributes = lambda l: {"word": l[0], "pos": l[1], "lemma": l[2], "wc": l[3]}
    dg.add_nodes_from([(l, attributes(cwb[l])) for l in range(len(cwb))])
    for l in range(len(cwb)):
        if cwb[l][6] == "root":
            dg.node[l]["root"] = "root"
    for i, line in enumerate(cwb):
        indeps = line[4][1:-1]
        if indeps != "":
            for rel in indeps.split("|"):
                match = re.search(relpattern, rel)
                relation = match.group("relation")
                offset = int(match.group("offset"))
                dg.add_edge(i+offset, i, {"relation": relation})
    return dg


def get_vertice_candidates(query_graph, target_graph):
    """For each vertice in query_graph return a list of possibly
    corresponding vertices from target_graph.
    
    Arguments:
    - `query_graph`:
    - `target_graph`:
    """
    mapping = {v: i for i, v in enumerate(sorted(query_graph.nodes()))}
    candidates = [[] for i in range(query_graph.number_of_nodes())]
    for vertice in query_graph.nodes():
        vm = mapping[vertice]
        if len(query_graph.node[vertice]) == 0:
            candidates[vm] = target_graph.nodes()
        else:
            candidates[vm] = [tv for tv in target_graph.nodes() if dictionary_match(query_graph.node[vertice], target_graph.node[tv])]
        candidates[vm] = set([tv for tv in candidates[vertice] if edge_match(query_graph, vertice, target_graph, tv)])
    # verify adjacency
    for vertice in query_graph.nodes():
        vm = mapping[vertice]
        for source, target, label in query_graph.out_edges(nbunch = [vertice], data = True):
            tm = mapping[target]
            candidates[vm] = set([x for x in candidates[vm] if any([dictionary_match(label, target_graph.edge[x][y]) for y in candidates[tm] if target_graph.has_edge(x, y)])])
            candidates[tm] = set([y for y in candidates[tm] if any([dictionary_match(label, target_graph.edge[x][y]) for x in candidates[vm] if target_graph.has_edge(x, y)])])
    return candidates


def dictionary_match(query_dictionary, target_dictionary):
    """Does target_vertice match query_vertice? I.e. are all keys from
    query_vertice in target_vertice and if yes, are their values
    equal?
    
    Arguments:
    - `query_dictionary`:
    - `target_dictionary`:
    """
    #return all([label in target_dictionary and re.search(r"^" + query_dictionary[label] + r"$", target_dictionary[label]) for label in query_dictionary])
    return all([label in target_dictionary and (query_dictionary[label] == ".+" or query_dictionary[label] == ".*" or query_dictionary[label] == target_dictionary[label]) for label in query_dictionary])


def edge_match(query_graph, query_vertice, target_graph, target_vertice):
    """Does vertice with target_index from target_graph have the same
    outgoing and incoming edges as vertice query_index from
    query_graph?
    
    Arguments:
    - `query_graph`:
    - `query_index`:
    - `target_graph`:
    - `target_index`:
    """
    query_outgoing = query_graph.out_edges(nbunch = [query_vertice], data = True)
    query_incoming = query_graph.in_edges(nbunch = [query_vertice], data = True)
    target_outgoing = target_graph.out_edges(nbunch = [target_vertice], data = True)
    target_incoming = target_graph.in_edges(nbunch = [target_vertice], data = True)
    if len(query_outgoing) > len(target_outgoing):
        return False
    if len(query_incoming) > len(target_incoming):
        return False
    outgoing_match = all([any([dictionary_match(qout[2], tout[2]) for tout in target_outgoing]) for qout in query_outgoing])
    incoming_match = all([any([dictionary_match(qin[2], tin[2]) for tin in target_incoming]) for qin in query_incoming])
    return outgoing_match and incoming_match


def export_to_adjacency_matrix(nx_graph, canonical=False):
    """Return an adjacency matrix representing nx_graph.
    
    Arguments:
    - `nx_graph`:
    """
    mapping = {}
    if canonical:
        mapping = {n: i for i, n in enumerate(canonical_order(nx_graph))}
    else:
        mapping = {n: i for i, n in enumerate(sorted(nx_graph.nodes()))}
    matrix = [[{} for j in range(nx_graph.number_of_nodes())] for i in range(nx_graph.number_of_nodes())]
    for v, l in nx_graph.nodes(data=True):
        vm = mapping[v]
        matrix[vm][vm] = l
    for s, t, l in nx_graph.edges(data=True):
        sm = mapping[s]
        tm = mapping[t]
        matrix[sm][tm] = l
    return matrix


def export_to_cwb_format(nx_graph):
    """Do actual formatting work.
    
    Arguments:
    - `nx_graph`:
    """
    output = []
    mapping = {n: i for i, n in enumerate(sorted(nx_graph.nodes()))}
    for v in sorted(nx_graph.nodes()):
        word = nx_graph.node[v]["word"]
        root = nx_graph.node[v].get("root", "")
        indeps = ["%s(%d,0)" % (l["relation"], mapping[s] - mapping[v]) for s, t, l in nx_graph.in_edges(v, data=True)]
        outdeps = ["%s(0,%d)" % (l["relation"], mapping[t] - mapping[v]) for s, t, l in nx_graph.out_edges(v, data=True)]
        indeps = "|" + "|".join(indeps)
        if len(indeps) > 1:
            indeps += "|"
        outdeps = "|" + "|".join(outdeps)
        if len(outdeps) > 1:
            outdeps += "|"
        output.append([word, "X", word, "X", indeps, outdeps, root])
    return output


def _get_vertice_tuple(nx_graph, vertice):
    """Return a tuple for the vertice that can be used for sorting
    
    Arguments:
    - `nx_graph`:
    - `vertice`:
    """
    label = tuple(sorted(nx_graph.node[vertice].items()))
    indegree = nx_graph.in_degree(vertice)
    outdegree = nx_graph.out_degree(vertice)
    inedgelabels = tuple(sorted([tuple(sorted(nx_graph.edge[s][t].items())) for s, t in nx_graph.in_edges(vertice)]))
    outedgelabels = tuple(sorted([tuple(sorted(nx_graph.edge[s][t].items())) for s, t in nx_graph.out_edges(vertice)]))
    return (label, indegree, outdegree, inedgelabels, outedgelabels)


def _dfs(nx_graph, vertice, vtuples):
    """Return vertice tuples in order of depth-first search starting from
    vertice
    
    Arguments:
    - `nx_graph`:
    - `vertice`:
    - `vtuples`:
    """
    order = []
    seen = set()
    agenda = [vertice]
    keyfunc = lambda v: vtuples[v]
    while len(agenda) > 0:
        v = agenda.pop(0)
        seen.add(v)
        order.append(vtuples[v])
        successors = sorted([x for x in nx_graph.successors(v) if x not in seen], key=keyfunc)
        agenda = _get_unique_order(nx_graph, successors, vtuples) + agenda
    return order


def _get_unique_order(nx_graph, sorted_vertices, vtuples):
    """Resolve any groups within sorted_vertices
    
    Arguments:
    - `nx_graph`:
    - `sorted_vertices`:
    - `vtuples`:
    """
    order = []
    keyfunc = lambda v: vtuples[v]
    for k, g in itertools.groupby(sorted_vertices, keyfunc):
        group = list(g)
        if len(group) == 1:
            order.append(group[0])
        elif len(group) == 0:
            raise Exception("Group should not be empty!")
        else:
            # We need more criteria for sorting
            vtuples_dfs = {v: tuple(_dfs(v) + [v]) for v in group}
            keyfunc_dfs = lambda v: vtuples_dfs[v]
            order.extend(sorted(group, key=keyfunc_dfs))
    return order


def canonical_order(nx_graph):
    """Return the vertices of nx_graph in canonical order
    
    Arguments:
    - `nx_graph`:
    """
    vertices = nx_graph.nodes()
    vtuples = {v: _get_vertice_tuple(nx_graph, v) for v in vertices}
    keyfunc = lambda v: vtuples[v]
    sorted_vertices = sorted(vertices, key=keyfunc)
    return _get_unique_order(nx_graph, sorted_vertices, vtuples)
