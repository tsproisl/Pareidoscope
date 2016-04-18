#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import functools
import json
import re
import sqlite3

import networkx

from pareidoscope.utils import nx_graph


def connect_to_database(filename):
    """Connect to database and return connection and cursor."""
    conn = sqlite3.connect(filename)
    # For the PCRE extension:
    # conn.enable_load_extension(True)
    # conn.load_extension("/usr/lib/sqlite3/pcre.so")
    c = conn.cursor()
    c.execute("PRAGMA page_size=4096")
    c.execute("PRAGMA cache_size=100000")
    return conn, c


def create_sql_query(query_graph):
    """Create an SQL query for the given query_graph."""
    sql_query = "SELECT s.sentence_id, s.graph, "
    where = []
    arguments = []
    sql_query += ", ".join(["tok_%s.position" % v for v in query_graph.nodes()])
    sql_query += " FROM sentences AS s"
    for vertex in query_graph.nodes():
        sql_query += " INNER JOIN tokens AS tok_%s ON s.sentence_id = tok_%s.sentence_id" % (vertex, vertex)
    for s, t, l in query_graph.edges(data=True):
        sql_query += " INNER JOIN dependencies AS dep_%s_%s ON (dep_%s_%s.governor_id = tok_%s.token_id) AND (dep_%s_%s.dependent_id = tok_%s.token_id)" % (s, t, s, t, s, s, t, t)
    sql_query += " WHERE "
    pos_lexical = set(["word", "pos", "lemma", "wc", "root"])
    neg_lexical = set(["not_%s" % pl for pl in pos_lexical])
    for vertex in query_graph.nodes():
        indegree = query_graph.in_degree(vertex)
        outdegree = query_graph.out_degree(vertex)
        if indegree > 0:
            where.append("tok_%s.indegree >= %d" % (vertex, indegree))
        if outdegree > 0:
            where.append("tok_%s.outdegree >= %d" % (vertex, outdegree))
        for k, v in query_graph.node[vertex].items():
            if k in pos_lexical:
                where.append("tok_%s.%s = ?" % (vertex, k))
                if k == "root":
                    arguments.append(v == "root")
                else:
                    arguments.append(v)
            elif k in neg_lexical:
                where.append("tok_%s.%s != ?" % (vertex, k))
                if k == "root":
                    arguments.append(v == "root")
                else:
                    arguments.append(v)
            elif k == "not_indep":
                for rel_item in v:
                    for rel in rel_item.split("|"):
                        where.append("? NOT IN (SELECT relation FROM dependencies WHERE dependent_id = tok_%s.token_id)" % vertex)
                        arguments.append(rel)
            elif k == "not_outdep":
                for rel_item in v:
                    for rel in rel_item.split("|"):
                        where.append("? NOT IN (SELECT relation FROM dependencies WHERE governor_id = tok_%s.token_id)" % vertex)
                        arguments.append(rel)
            else:
                raise Exception("Unsupported key: %s" % k)
    for s, t, l in query_graph.edges(data=True):
        if "relation" in l:
            where.append("dep_%s_%s.relation = ?" % (s, t))
            arguments.append(l["relation"])
    sql_query += " AND ".join(where)
    return sql_query, tuple(arguments)


def get_candidates(c, graph):
    """Get candidate tokens for each vertex in the graph from the
    database.

    Arguments:
    - `c`: Database cursor
    - `graph`:

    """
    mapping = {v: i for i, v in enumerate(sorted(graph.nodes()))}
    sentpos = {}
    sentences = []
    queries = [(i, _create_sql_query(graph, v)) for v, i in mapping.items()]
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
    sent_intersect = functools.reduce(lambda x, y: x.intersection(y), sentences)
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
    for key, value in graph.node[v].items():
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
        for key, value in l.items():
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
        for key, value in l.items():
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
    """Get candidate tokens for each vertex in the graph from the
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
    subgraph = json.dumps(list(networkx.generate_adjlist(canonized)), ensure_ascii=False, sort_keys=True)
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
