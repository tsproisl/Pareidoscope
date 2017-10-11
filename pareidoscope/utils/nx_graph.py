#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import itertools
import re

import networkx


def create_nx_digraph(adj_matrix):
    """Return a networkx.DiGraph object of the adjacency matrix."""
    dg = networkx.DiGraph()
    dg.add_nodes_from([(i, adj_matrix[i][i]) for i in range(len(adj_matrix))])
    for i in range(len(adj_matrix)):
        for j in range(len(adj_matrix)):
            if i == j:
                continue
            if adj_matrix[i][j]:
                dg.add_edge(i, j, **adj_matrix[i][j])
    return dg


def create_nx_digraph_from_cwb(cwb, origid=None):
    """Return a networkx.DiGraph object of the CWB representation."""
    relpattern = re.compile(r"^(?P<relation>[^(]+)[(](?P<offset>-?\d+)(?:&apos;|')*,0(?:&apos;|')*[)]$")
    dg = networkx.DiGraph()
    if origid is not None:
        dg.graph["origid"] = origid
    attributes = lambda l: {"word": l[0], "pos": l[1], "lemma": l[2], "wc": l[3]}
    dg.add_nodes_from([(l, attributes(cwb[l])) for l in range(len(cwb))])
    for l in range(len(cwb)):
        if cwb[l][6] == "root":
            dg.nodes[l]["root"] = "root"
    for i, line in enumerate(cwb):
        indeps = line[4]
        if indeps != "|":
            for rel in indeps.strip("|").split("|"):
                match = re.search(relpattern, rel)
                relation = match.group("relation")
                offset = int(match.group("offset"))
                # ignore dependency relations for punctuation
                if relation == "punct":
                    continue
                if offset != 0:
                    dg.add_edge(i + offset, i, relation=relation)
    # remove unconnected vertices, e.g. punctuation in the SD model
    for v, l in list(dg.nodes(data=True)):
        if "root" not in l and dg.degree[v] == 0:
            dg.remove_node(v)
    # make sure that the remaining vertices are consecutively labeled
    dg = ensure_consecutive_vertices(dg)
    return dg


def create_nx_digraph_from_conllu(conllu, origid=None):
    """Return a networkx.DiGraph object of the CoNLL-U representation."""
    dg = networkx.DiGraph()
    if origid is not None:
        dg.graph["origid"] = origid
    attributes = lambda l: {"word": l[1], "lemma": l[2], "wc": l[3], "pos": l[4]}
    dg.add_nodes_from([(l, attributes(conllu[l])) for l in range(len(conllu))])
    id_to_enumeration = {conllu[l][0]: l for l in range(len(conllu))}
    for l in range(len(conllu)):
        if conllu[l][7] == "root":
            dg.nodes[l]["root"] = "root"
    for i, line in enumerate(conllu):
        relations = set()
        if line[8] != "_":
            for rel in line[8].split("|"):
                gov, relation = rel.split(":", maxsplit=1)
                if relation != "root":
                    governor = id_to_enumeration[gov]
                    relations.add((governor, relation))
        elif line[7] != "_":
            if line[7] != "root":
                relations.add((id_to_enumeration[line[6]], line[7]))
        for governor, relation in relations:
            if relation == "root" or relation == "punct":
                continue
            dg.add_edge(governor, i, relation=relation)
    # remove unconnected vertices, e.g. punctuation in the SD model
    for v, l in list(dg.nodes(data=True)):
        if "root" not in l and dg.degree[v] == 0:
            dg.remove_node(v)
    # make sure that the remaining vertices are consecutively labeled
    dg = ensure_consecutive_vertices(dg)
    return dg


def is_sensible_graph(nx_graph):
    """Check if graph is a sensible syntactic representation of a
    sentence, i.e. rooted, connected, sensible outdegree, sensible
    density, …

    """
    # are the vertices consecutively labeled?
    if sorted(nx_graph.nodes()) != list(range(nx_graph.number_of_nodes())):
        raise Exception("Vertices are not consecutively labeled")
    # is there a vertex explicitly labeled as "root"?
    roots = [v for v, l in nx_graph.nodes(data=True) if "root" in l]
    if len(roots) != 1:
        return False
    # is the graph connected?
    if not networkx.is_weakly_connected(nx_graph):
        return False
    # is the "root" vertex really a root, i.e. is there a path to
    # every other vertex?
    root = roots[0]
    other_vertices = set(nx_graph.nodes())
    other_vertices.remove(root)
    if not all([networkx.has_path(nx_graph, root, v) for v in other_vertices]):
        return False
    # # do the vertices have sensible outdegrees <= 10?
    if any([nx_graph.out_degree[v] > 10 for v in nx_graph.nodes()]):
        return False
    # is the graph overly dense, i.e. is there a vertex with an
    # extended star (neighbors + edges between them) with more than 18
    # edges?
    if any([nx_graph.subgraph(set([v] + list(nx_graph.predecessors(v)) + list(nx_graph.successors(v)))).number_of_edges() > 18 for v in nx_graph.nodes()]):
        return False
    return True


def get_vertex_candidates(query_graph, target_graph):
    """For each vertex in query_graph return a list of possibly
    corresponding vertices from target_graph.

    """
    candidates = [[] for v in query_graph.nodes()]
    for vertex in query_graph.nodes():
        if len(query_graph.nodes[vertex]) == 0:
            candidates[vertex] = target_graph.nodes()
        else:
            candidates[vertex] = [tv for tv in target_graph.nodes() if dictionary_match(query_graph.nodes[vertex], target_graph.nodes[tv])]
        query_in = query_graph.in_degree[vertex]
        query_out = query_graph.out_degree[vertex]
        candidates[vertex] = [tv for tv in candidates[vertex] if (query_in <= target_graph.in_degree[tv]) and (query_out <= target_graph.out_degree[tv])]
        # negated edges
        not_indep = query_graph.nodes[vertex].get("not_indep")
        if not_indep is not None:
            not_indep = set(not_indep)
            candidates[vertex] = [tv for tv in candidates[vertex] if len(not_indep & set([l["relation"] for s, t, l in target_graph.in_edges(tv, data=True)])) == 0]
        not_outdep = query_graph.nodes[vertex].get("not_outdep")
        if not_outdep is not None:
            not_outdep = set(not_outdep)
            candidates[vertex] = [tv for tv in candidates[vertex] if len(not_outdep & set([l["relation"] for s, t, l in target_graph.out_edges(tv, data=True)])) == 0]
        candidates[vertex] = set(candidates[vertex])
    # verify adjacency and edge labels
    for s, t, l in query_graph.edges(data=True):
        source_candidates = set([])
        target_candidates = set([])
        for cs, ct in itertools.product(candidates[s], candidates[t]):
            if target_graph.has_edge(cs, ct):
                if dictionary_match(l, target_graph.edges[cs, ct]):
                    source_candidates.add(cs)
                    target_candidates.add(ct)
        candidates[s] = source_candidates
        candidates[t] = target_candidates
    return candidates


def dictionary_match(query_dictionary, target_dictionary):
    """Does target_vertex match query_vertex? I.e. are all keys from
    query_vertex in target_vertex and if yes, are their values equal?

    """
    results = []
    for label in query_dictionary:
        if label.startswith("not_"):
            if label == "not_indep" or label == "not_outdep":
                continue
            pos_label = label[4:]
            results.append(pos_label in target_dictionary and query_dictionary[label] != target_dictionary[pos_label])
        else:
            results.append(label in target_dictionary and query_dictionary[label] == target_dictionary[label])
    return all(results)
    # return all([label in target_dictionary and (query_dictionary[label] == target_dictionary[label] or re.search(r"^" + str(query_dictionary[label]) + r"$", str(target_dictionary[label]))) for label in query_dictionary])


def export_to_adjacency_matrix(nx_graph, canonical=False):
    """Return an adjacency matrix representing nx_graph."""
    # identity mapping
    mapping = {v: v for v in nx_graph.nodes()}
    # or mapping to canonical order
    if canonical:
        mapping = {v: i for i, v in enumerate(canonical_order(nx_graph))}
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
    """Do actual formatting work."""
    output = []
    for v in sorted(nx_graph.nodes()):
        word = nx_graph.nodes[v]["word"]
        pos = nx_graph.nodes[v].get("pos", "X")
        lemma = nx_graph.nodes[v].get("lemma", word)
        wc = nx_graph.nodes[v].get("wc", "X")
        root = nx_graph.nodes[v].get("root", "")
        indeps = ["%s(%d,0)" % (l["relation"], s - v) for s, t, l in nx_graph.in_edges(v, data=True)]
        outdeps = ["%s(0,%d)" % (l["relation"], t - v) for s, t, l in nx_graph.out_edges(v, data=True)]
        indeps = "|" + "|".join(indeps)
        if len(indeps) > 1:
            indeps += "|"
        outdeps = "|" + "|".join(outdeps)
        if len(outdeps) > 1:
            outdeps += "|"
        output.append([word, pos, lemma, wc, indeps, outdeps, root])
    return output


def export_to_chemical_format(graph, vertex_dict, edge_dict):
    """Export to chemical format for use with Gaston
    (http://www.liacs.nl/~snijssen/gaston/index.html).

    """
    export = ["t # "]
    vmax = None
    try:
        vmax = max(vertex_dict.values())
    except ValueError:
        vmax = 0
    for v in sorted(graph.nodes()):
        word = graph.nodes[v]["word"]
        pos = graph.nodes[v].get("pos", "X")
        lemma = graph.nodes[v].get("lemma", word)
        wc = graph.nodes[v].get("wc", "X")
        t = (word, pos, lemma, wc)
        if t not in vertex_dict:
            vmax += 1
            vertex_dict[t] = vmax
        export.append("v %d %d" % (v, vertex_dict[t]))
        emax = None
    try:
        emax = max(edge_dict.values())
    except ValueError:
        emax = 0
    for s, t, l in sorted(graph.edges(data=True)):
        rel = l["relation"]
        if rel not in edge_dict:
            emax += 1
            edge_dict[rel] = emax
        export.append("e %d %d %d" % (s, t, edge_dict[rel]))
    return export


def is_purely_structural(nx_graph):
    """Is query_graph purely structural, i.e. does it contain no
    restrictions on vertex and edge labels?

    """
    vertices = all([_is_unrestricted(l) for v, l in nx_graph.nodes(data=True)])
    edges = all([_is_unrestricted(l) for s, t, l in nx_graph.edges(data=True)])
    return vertices and edges


def _is_unrestricted(dictionary):
    """Is the dictionary unrestricted, i.e. is it empty or does it only
    have ".+" or ".*" as values?

    """
    if dictionary == {}:
        return True
    return all([val == ".+" or val == ".*" for val in dictionary.values()])


def _get_vertex_tuple(nx_graph, vertex):
    """Return a tuple for the vertex that can be used for sorting"""
    other_vertices = set(nx_graph.nodes())
    other_vertices.remove(vertex)
    root = all((networkx.has_path(nx_graph, vertex, x) for x in other_vertices))
    antiroot = all((networkx.has_path(nx_graph, x, vertex) for x in other_vertices))
    star_center = all((nx_graph.has_edge(vertex, x) or nx_graph.has_edge(x, vertex) for x in other_vertices))
    choke_point = None
    if root or antiroot or star_center:
        choke_point = True
    else:
        choke_point = all((networkx.has_path(nx_graph, vertex, x) or networkx.has_path(nx_graph, x, vertex) for x in other_vertices))
    indegree = nx_graph.in_degree[vertex]
    outdegree = nx_graph.out_degree[vertex]
    label = tuple(sorted(nx_graph.nodes[vertex].items()))
    inedgelabels = tuple(sorted([tuple(sorted(nx_graph.edges[s, t].items())) for s, t in nx_graph.in_edges(vertex)]))
    outedgelabels = tuple(sorted([tuple(sorted(nx_graph.edges[s, t].items())) for s, t in nx_graph.out_edges(vertex)]))
    return (root, antiroot, star_center, choke_point, indegree, outdegree, label, inedgelabels, outedgelabels)


def _dfs(nx_graph, vertex, vtuples, return_ids=False, blacklist=[]):
    """Return vertex tuples in order of depth-first search starting from
    vertex

    """
    order = []
    seen = set(blacklist)
    agenda = [vertex]
    keyfunc = lambda v: vtuples[v]
    while len(agenda) > 0:
        v = agenda.pop(0)
        if v in seen:
            continue
        seen.add(v)
        if return_ids:
            order.append(v)
        else:
            order.append(vtuples[v])
        successors = sorted([x for x in nx_graph.successors(v) if x not in seen], key=keyfunc)
        agenda = _get_unique_order(nx_graph, successors, vtuples, blacklist=list(seen)) + agenda
    return order


def _get_unique_order(nx_graph, sorted_vertices, vtuples, blacklist=[]):
    """Resolve any groups within sorted_vertices"""
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
            vtuples_dfs = {v: tuple(_dfs(nx_graph, v, vtuples, blacklist=blacklist)) for v in group}
            keyfunc_dfs = lambda v: (vtuples_dfs[v], v)
            order.extend(sorted(group, key=keyfunc_dfs))
    return order


def canonical_order(nx_graph):
    """Return the vertices of nx_graph in canonical order"""
    vertices = nx_graph.nodes()
    vtuples = {v: _get_vertex_tuple(nx_graph, v) for v in vertices}
    roots = [v for v in vtuples if vtuples[v][0]]
    antiroots = [v for v in vtuples if vtuples[v][1]]
    if len(roots) == 1:
        return _dfs(nx_graph, roots[0], vtuples, return_ids=True)
    if len(antiroots) == 1:
        return list(reversed(_dfs(nx_graph.reverse(), antiroots[0], vtuples, return_ids=True)))
    keyfunc = lambda v: vtuples[v]
    sorted_vertices = sorted(vertices, key=keyfunc)
    return _get_unique_order(nx_graph, sorted_vertices, vtuples)


def canonize(nx_graph, order=False):
    """Return canonized copy of nx_graph"""
    co = canonical_order(nx_graph)
    mapping = {v: i for i, v in enumerate(co)}
    canonized = networkx.DiGraph(**nx_graph.graph)
    for v, l in nx_graph.nodes(data=True):
        canonized.add_node(mapping[v], **l)
    for s, t, l in nx_graph.edges(data=True):
        canonized.add_edge(mapping[s], mapping[t], **l)
    if order:
        return canonized, co
    else:
        return canonized


def skeletize(nx_graph, only_vertices=False):
    """Return skeleton copy of nx_graph"""
    skeleton = networkx.DiGraph(**nx_graph.graph)
    for s, t, l in nx_graph.edges(data=True):
        if only_vertices:
            ll = {k: v for k, v in l.items()}
            skeleton.add_edge(s, t, **ll)
        else:
            skeleton.add_edge(s, t)
    return skeleton


def get_choke_point(nx_graph):
    """Return one of the choke point vertices if there are any.

    Arguments:
        nx_graph:

    Returns:
        The first root vertex in canonical order. If there aren't
        any, the first antiroot vertex in canonical order. Else the
        first other choke point in canonical order.

    """
    vertices = canonical_order(nx_graph)
    vtuples = {v: _get_vertex_tuple(nx_graph, v) for v in vertices}
    roots = [v for v in vertices if vtuples[v][0]]
    antiroots = [v for v in vertices if vtuples[v][1]]
    choke_points = [v for v in vertices if vtuples[v][2]]
    if len(roots) >= 1:
        return roots[0]
    if len(antiroots) >= 1:
        return antiroots[0]
    if len(choke_points) >= 1:
        return choke_points[0]
    return None


def is_star(nx_graph, return_centers=False):
    """Check if the graph is a star, i.e. if it has one vertex that is
    adjacent to all others.

    """
    vertices = set(nx_graph.nodes())
    if return_centers:
        centers = [v for v in vertices if set([v] + list(nx_graph.predecessors(v)) + list(nx_graph.successors(v))) == vertices]
        is_star = len(centers) >= 1
        return is_star, set(centers)
    else:
        return any((set([v] + list(nx_graph.predecessors(v)) + list(nx_graph.successors(v))) == vertices for v in vertices))


def is_star_center(nx_graph, v):
    """Check if the graph is a star and the vertex v is its center, i.e.
    if v is adjacent to all other vertices.

    """
    vertices = set(nx_graph.nodes())
    return set([v] + list(nx_graph.predecessors(v)) + list(nx_graph.successors(v))) == vertices


def ensure_consecutive_vertices(graph):
    """Make sure that the n vertices of the graph have indices 0 to
    n-1.

    """
    if sorted(graph.nodes()) == list(range(graph.number_of_nodes())):
        return graph
    else:
        mapping = {v: i for i, v in enumerate(sorted(graph.nodes()))}
        new_graph = networkx.DiGraph(**graph.graph)
        for vertex, label in graph.nodes(data=True):
            new_graph.add_node(mapping[vertex], **label)
        for s, t, l in graph.edges(data=True):
            new_graph.add_edge(mapping[s], mapping[t], **l)
        return new_graph
