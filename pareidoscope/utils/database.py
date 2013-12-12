#!/usr/bin/python
# -*- coding: utf-8 -*-

import json
import operator
import re

import networkx

from pareidoscope.utils import nx_graph


def get_candidates(c, graph):
    """Get candidate tokens for each vertice in the graph from the
    database.
    
    Arguments:
    - `c`: Database cursor
    - `graph`:

    """
    mapping = {v: i for i, v in enumerate(sorted(graph.nodes()))}
    sentpos = {}
    sentences = []
    queries = [(i, _create_sql_query(graph, v)) for v, i in mapping.iteritems()]
    for i, (query, args) in queries:
        sentpos[i] = {}
        vsents = set()
        for row in c.execute(query, args):
            sentid, position = row
            if sentid not in sentpos[i]:
                sentpos[i][sentid] = set()
            sentpos[i][sentid].add(position)
            vsents.add(sentid)
        sentences.append(vsents)
    sent_intersect = reduce(lambda x, y: x.intersection(y), sentences)
    candidates = {sentid: [sentpos[i][sentid] for i in sorted(sentpos)] for sentid in sent_intersect}
    return candidates


def _create_sql_query(graph, v):
    """Create an SQL query for the given node and return a tuple
    consisting of query string and parameters.
    
    Arguments:
    - `graph`:
    - `v`:

    """
    query_select = "SELECT DISTINCT tok.sentid, tok.position"
    query_from = "FROM tokens as tok INNER JOIN types as t USING (typeid)"
    query_where = []
    arguments = []
    pos_lexical = set(["word", "pos", "lemma", "wc", "root"])
    neg_lexical = set(["not_%s" % pl for pl in pos_lexical])
    match_all = set([".*", ".+", "^.*$", "^.+$"])
    for key, value in graph.node[v].iteritems():
        # check if value could be a regular expression
        if key in pos_lexical:
            if might_contain_re(value):
                if value not in match_all:
                    query_where.append("t.%s REGEXP ?" % key)
                    arguments.append("^%s$" % value)
            else:
                query_where.append("t.%s=?" % key)
                arguments.append(value)
        elif key in neg_lexical:
            if might_contain_re(value):
                query_where.append("t.%s NOT REGEXP ?" % key)
                arguments.append("^%s$" % value)
            else:
                query_where.append("t.%s!=?" % key)
                arguments.append(value)
        elif key == "not_indep":
            relations = value.split("|")
            for rel in relations:
                query_where.append("? NOT IN (SELECT indep FROM indeps WHERE indeps.typeid=t.typeid)")
                arguments.append(rel)
        elif key == "not_outdep":
            relations = value.split("|")
            for rel in relations:
                query_where.append("? NOT IN (SELECT outdep FROM outdeps WHERE outdeps.typeid=t.typeid)")
                arguments.append(rel)
        else:
            raise Exception("Unsupported key: %s" % key)
    query_where.append("t.indeg>=?")
    arguments.append(graph.in_degree(v))
    query_where.append("t.outdeg>=?")
    arguments.append(graph.out_degree(v))
    # dependency relations only support alternations, e.g. "dobj|iobj"
    # to express any object
    incounter = 0
    for s, t, l in graph.in_edges(v, data=True):
        for key, value in l.iteritems():
            if key == "relation":
                if value in match_all:
                    continue
                incounter += 1
                query_from += " INNER JOIN indeps AS o%d USING (typeid)" % incounter
                relations = value.split("|")
                if len(relations) == 1:
                    query_where.append("o%d.indep=?" % incounter)
                    arguments.append(value)
                else:
                    query_where.append("o%d.indep IN (%s)" % (incounter, ", ".join(["?"] * len(relations))))
                    arguments.extend(relations)
            else:
                raise Exception("Unsupported key: %s" % key)
    outcounter = 0
    for s, t, l in graph.out_edges(v, data=True):
        for key, value in l.iteritems():
            if key == "relation":
                if value in match_all:
                    continue
                outcounter += 1
                query_from += " INNER JOIN outdeps AS o%d USING (typeid)" % outcounter
                relations = value.split("|")
                if len(relations) == 1:
                    query_where.append("o%d.outdep=?" % outcounter)
                    arguments.append(value)
                else:
                    query_where.append("o%d.outdep IN (%s)" % (outcounter, ", ".join(["?"] * len(relations))))
                    arguments.extend(relations)
            else:
                raise Exception("Unsupported key: %s" % key)
    query = " ".join([query_select, query_from, "WHERE", " AND ".join(query_where)])
    return query, tuple(arguments)


def might_contain_re(s):
    """Return if the string might contain a regular expression, i.e. any
    non-alphanumeric characters
    
    Arguments:
    - `s`:

    """
    reg = re.compile(r"^\w+$", flags=re.UNICODE)
    return re.search(reg, s) is None


def regexp(expression, item):
    """Does expression match item?
    
    Arguments:
    - `expression`:
    - `item`:

    """
    reg = re.compile(expression)
    return reg.search(item) is not None


def get_structure_candidates(c, graph):
    """Get candidate tokens for each vertice in the graph from the
    database.
    
    Arguments:
    - `c`: Database cursor
    - `graph`:

    """
    skel = nx_graph.skeletize(graph)
    mapping = {v: i for i, v in enumerate(sorted(skel.nodes()))}
    candidates = {}
    canonized, order = nx_graph.canonize(skel, order=True)
    length = len(order)
    subgraph = json.dumps(list(networkx.generate_adjlist(canonized)))
    subgraphid = c.execute("SELECT subgraphid FROM subgraphs WHERE subgraph=?", (subgraph,)).fetchall()
    if subgraphid == []:
        for row in c.execute("SELECT subgraphid, subgraph FROM subgraphs WHERE length=?", (length,)):
            sgid, sgadj = row
            sg = networkx.parse_adjlist(json.loads(sgadj), nodetype=int, create_using=networkx.DiGraph())
            if networkx.is_isomorphic(sg, canonized):
                subgraphid = [(sgid,)]
                break
    if subgraphid == []:
        return candidates
    subgraphid = subgraphid[0][0]
    query = "SELECT sentid, %s FROM subgraphs%d WHERE subgraphid=?" % (", ".join("v%d" % i for i in range(1, length + 1)), length)
    for row in c.execute(query, (subgraphid,)):
        sentid = row[0]
        positions = row[1:]
        if sentid not in candidates:
            candidates[sentid] = [set() for _ in range(length)]
        for j, pos in enumerate(positions):
            i = mapping[order[j]]
            candidates[sentid][i].add(pos)
    return candidates
