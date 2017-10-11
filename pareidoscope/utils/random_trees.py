#!/usr/bin/python
# -*- coding: utf-8 -*-

import itertools
import os
import random
import sys

import networkx

script_directory = os.path.abspath(os.path.dirname(sys.argv[0]))
if script_directory not in sys.path:
    sys.path.insert(0, script_directory)

import nx_graph


def get_random_near_tree(nr_of_vertices, vertex_label_distri, edge_label_distri, max_outdegree=0):
    """Create a random near tree with nr_of_vertices vertices. The
    vertex and edge labels are determined by vertex_label_distri and
    edge_label_distri.

    Arguments:
    - `nr_of_vertices`:
    - `vertex_label_distri`:
    - `edge_label_distri`:
    - `max_outdegree`:
    """
    pass


def get_random_tree(nr_of_vertices, vertex_label_distri, edge_label_distri, degree_distri, max_outdegree=0, no_root=False, underspec=0.0):
    """Create a random tree with nr_of_vertices vertices. The vertex
    and edge labels are determined by vertex_label_distri and
    edge_label_distri.

    Arguments:
    - `nr_of_vertices`:
    - `vertex_label_distri`:
    - `edge_label_distri`:
    - `degree_distri`:
    - `max_outdegree`:
    """
    root = None
    directed_tree = networkx.DiGraph()
    if nr_of_vertices == 1:
        root = 0
        directed_tree.add_node(root)
    else:
        undirected_tree = create_tree_skeleton(nr_of_vertices, degree_distri, max_outdegree)
        root = random.choice(list(itertools.chain.from_iterable([[v] * undirected_tree.degree[v] for v in undirected_tree.nodes()])))
        directed_tree.add_edges_from(networkx.bfs_edges(undirected_tree, root))
    if not no_root:
        directed_tree.nodes[root]["root"] = "root"
    add_vertex_labels(directed_tree, vertex_label_distri, underspec)
    add_edge_labels(directed_tree, edge_label_distri, underspec)
    return directed_tree


def get_powerlaw_tree_sequence(nr_of_vertices):
    """Return a powerlaw degree sequence

    Arguments:
    - `nr_of_vertices`:
    """
    if nr_of_vertices == 1:
        return [0]
    try:
        degree_sequence = networkx.random_powerlaw_tree_sequence(nr_of_vertices, tries=1000)
    except networkx.NetworkXError:
        degree_sequence = get_powerlaw_tree_sequence(nr_of_vertices)
    return degree_sequence


def create_tree_skeleton(nr_of_vertices, degree_distri, max_outdegree):
    """Create a random undirected tree without any labels.

    Arguments:
    - `nr_of_vertices`:
    - `degree_distri`:
    - `max_outdegree`:
    """
    degree_sum = 2 * (nr_of_vertices - 1)
    degree_sequence = None
    if degree_distri == "uniform":
        degree_sequence = distribution(nr_of_vertices, degree_sum)
        if max_outdegree > 1:
            while max(degree_sequence) > max_outdegree:
                degree_sequence = distribution(nr_of_vertices, degree_sum)
    elif degree_distri == "zipf":
        mini = int(round(degree_sum * 0.75))
        maxi = int(round(degree_sum * 1.25))
        while True:
            degree_sequence = networkx.utils.zipf_sequence(nr_of_vertices)
            while sum(degree_sequence) < mini or sum(degree_sequence) > maxi:
                degree_sequence = networkx.utils.zipf_sequence(nr_of_vertices)
            x = [_ / float(sum(degree_sequence)) for _ in degree_sequence]
            while sum(degree_sequence) != degree_sum:
                degree_sequence = adjust_distribution(degree_sequence, x, degree_sum, nr_of_vertices - 1)
            if max(degree_sequence) <= max_outdegree:
                break
    elif degree_distri == "powerlaw":
        degree_sequence = get_powerlaw_tree_sequence(nr_of_vertices)
        if max_outdegree > 1:
            while max(degree_sequence) > max_outdegree:
                degree_sequence = get_powerlaw_tree_sequence(nr_of_vertices)
    undirected_tree = networkx.degree_sequence_tree(degree_sequence)
    return undirected_tree


def add_vertex_labels(tree, vertex_label_distri, underspec):
    """Add vertex labels to tree according to vertex_label_distri.

    Arguments:
    - `tree`:
    - `vertex_label_distri`:
    """
    for vertex in tree.nodes():
        if random.random() < underspec:
            tree.nodes[vertex]["word"] = ".+"
        else:
            tree.nodes[vertex]["word"] = random.choice(vertex_label_distri)


def add_edge_labels(tree, edge_label_distri, underspec):
    """Add vertex labels to tree according to vertex_label_distri.

    Arguments:
    - `tree`:
    - `vertex_label_distri`:
    """
    for s, t in tree.edges():
        if random.random() < underspec:
            tree.edges[s, t]["relation"] = ".+"
        else:
            tree.edges[s, t]["relation"] = random.choice(edge_label_distri)


def distribution(n, total):
    """Return n random natural numbers that sum up to total and follow
    a uniform distribution.

    Arguments:
    - `n`:
    - `total`:
    """
    maximum = total - (n - 1)
    p = [0] + sorted(random.random() for _ in range(n - 1)) + [1]
    distri_1 = [p[i+1] - p[i] for i in range(n)]
    distri_total = [int(total * _) for _ in distri_1]
    # adjust lowest values
    distri_total = [max(1, _) for _ in distri_total]
    # adjust highest values
    distri_total = [min(maximum, _) for _ in distri_total]
    # adjust remaining values until total is correct
    while sum(distri_total) != total:
        distri_total = adjust_distribution(distri_total, distri_1, total, maximum)
    return distri_total


def adjust_distribution(dist_to_adjust, random_dist, total, maximum):
    """Adjust dist_to_adjust so that it sums up to total, no value is
    larger that maximum or smaller than one and relative difference to
    random_dist is minimal.

    Arguments:
    - `dist_to_adjust`:
    - `random_dist`:
    - `total`:
    - `maximum`:
    """
    deviations = [x - y for (x, y) in zip([_ / float(total) for _ in dist_to_adjust], random_dist)]
    deviations = list(enumerate(deviations))
    comp = maximum
    adj = 1
    if sum(dist_to_adjust) < total:
        deviations.sort(key=lambda x: x[1])
    else:
        deviations.sort(key=lambda x: x[1], reverse=True)
        comp = 1
        adj = -1
    for (idx, _) in deviations:
        if dist_to_adjust[idx] == comp:
            continue
        dist_to_adjust[idx] += adj
        break
    return dist_to_adjust


def create_distribution(size, distribution, prefix):
    """Create data according to distribution.

    Arguments:
    - `size`:
    - `distribution`:
    """
    vocabulary = []
    if distribution == "uniform":
        vocabulary = ["%s%05d" % (prefix, i) for i in range(size)]
    elif distribution == "zipf":
        zs = (int(round(z)) for z in networkx.utils.zipf_sequence(size))
        for i, j in enumerate(zs):
            vocabulary.extend(["%s%05d" % (prefix, i)] * j)
    return vocabulary


def get_length(sent_dist, mu, sigma, min_length, max_length):
    """Return an integer.

    Arguments:
    - `sent_dist`:
    - `mu`:
    - `sigma`:
    - `min_length`:
    - `max_length`:
    """
    length = None
    if sent_dist == "uniform":
        length = random.randint(min_length, max_length)
    elif sent_dist == "normal":
        length = int(round(random.normalvariate(mu, sigma)))
        while length < min_length or length > max_length:
            length = int(round(random.normalvariate(mu, sigma)))
    return length


def split_tree(tree):
    """Split tree into two subtrees and return queries.

    Arguments:
    - `tree`:
    """
    # choose one edge for splitting
    s, t = random.choice(tree.edges())
    t_bunch = set(networkx.dfs_preorder_nodes(tree, t))
    s_bunch = set(tree.nodes()) - t_bunch
    a = tree.subgraph(s_bunch).copy()
    b = tree.subgraph(t_bunch).copy()
    # give edge to either source or target vertex
    if random.choice(["source", "target"]) == "source":
        a.add_node(t, word=".+")
        a.add_edge(s, t, relation=tree[s][t]["relation"])
    else:
        b.add_node(s, word=".+")
        b.add_edge(s, t, relation=tree[s][t]["relation"])
    n = tree.copy()
    for vertex in n.nodes():
        n.nodes[vertex]["word"] = ".+"
    for s, t in n.edges():
        n.edges[s, t]["relation"] = ".+"
    r1 = n.copy()
    for vertex in a.nodes():
        r1.nodes[vertex]["word"] = a.nodes[vertex]["word"]
    for s, t in a.edges():
        r1.edges[s, t]["relation"] = a.edge[s][t]["relation"]
    c1 = n.copy()
    for vertex in b.nodes():
        c1.nodes[vertex]["word"] = b.nodes[vertex]["word"]
    for s, t in b.edges():
        c1.edges[s, t]["relation"] = b.edge[s][t]["relation"]
    return a, b, r1, c1, n


def cwb_format(tree, length, sid):
    """Do actual formatting work.

    Arguments:
    - `tree`:
    - `length`:
    """
    lines = []
    lines.append('<s id="%d" len="%d">' % (sid, length))
    lines.extend(["\t".join(l) for l in nx_graph.export_to_cwb_format(tree)])
    lines.append("</s>")
    return "\n".join(lines)
