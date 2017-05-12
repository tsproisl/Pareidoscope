#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import functools
import re
import sqlite3


def connect_to_database(filename, re=False):
    """Connect to database and return connection and cursor."""
    conn = sqlite3.connect(filename)
    # For the PCRE extension:
    # conn.enable_load_extension(True)
    # conn.load_extension("/usr/lib/sqlite3/pcre.so")
    c = conn.cursor()
    c.execute("PRAGMA page_size=4096")
    c.execute("PRAGMA cache_size=100000")
    if re:
        conn.create_function("REGEXP", 2, regexp)
    return conn, c


def sentence_candidates(c, g):
    """Get candidate sentences (no token candidates!) for the query
    graph.

    """
    sentence_ids = []
    for vertex in g.nodes():
        sql_query = "SELECT DISTINCT sentence_id FROM tokens WHERE "
        where = []
        args = []
        pos_lexical = set(["word", "pos", "lemma", "wc", "root"])
        neg_lexical = set(["not_%s" % pl for pl in pos_lexical])
        indegree = g.in_degree(vertex)
        outdegree = g.out_degree(vertex)
        if indegree > 0:
            where.append("indegree >= ?")
            args.append(indegree)
        if outdegree > 0:
            where.append("outdegree >= ?")
            args.append(outdegree)
        for k, v in g.node[vertex].items():
            if k in pos_lexical:
                where.append("%s = ?" % k)
                if k == "root":
                    args.append(v == "root")
                else:
                    args.append(v)
            elif k in neg_lexical:
                k = k[4:]
                where.append("%s != ?" % k)
                if k == "root":
                    args.append(v == "root")
                else:
                    args.append(v)
            elif k == "not_indep":
                relations = []
                for rel in v:
                    relations.append("relation = ?")
                    args.append(rel)
                where.append("NOT EXISTS (SELECT 1 FROM dependencies WHERE dependent_id = token_id AND (%s))" % " OR ".join(relations))
            elif k == "not_outdep":
                relations = []
                for rel in v:
                    relations.append("relation = ?")
                    args.append(rel)
                where.append("NOT EXISTS (SELECT 1 FROM dependencies WHERE governor_id = token_id AND (%s))" % " OR ".join(relations))
            else:
                raise Exception("Unsupported key: %s" % k)
        sql_query += " AND ".join(where)
        sentence_ids.append(set([r[0] for r in c.execute(sql_query, args).fetchall()]))
    candidate_ids = functools.reduce(lambda x, y: x.intersection(y), sentence_ids)
    candidate_sentences = [r[0] for r in c.execute("SELECT graph FROM sentences WHERE sentence_id IN (%s)" % ", ".join([str(_) for _ in candidate_ids])).fetchall()]
    return candidate_sentences


# Only used in pareidoscope_collexeme_analysis_db
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


def _create_sql_query(graph, v):
    """Create an SQL query for the given node and return a tuple
    consisting of query string and parameters.

    Arguments:
    - `graph`:
    - `v`:

    """
    query_select = "SELECT DISTINCT tok.sentence_id, tok.position"
    query_from = "FROM tokens as tok"
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
                    query_where.append("tok.%s REGEXP ?" % key)
                    arguments.append("^%s$" % value)
            else:
                query_where.append("tok.%s=?" % key)
                arguments.append(value)
        elif key in neg_lexical:
            if might_contain_re(value):
                query_where.append("tok.%s NOT REGEXP ?" % key)
                arguments.append("^%s$" % value)
            else:
                query_where.append("tok.%s!=?" % key)
                arguments.append(value)
        elif key == "not_indep":
            relations = value.split("|")
            for rel in relations:
                query_where.append("? NOT IN (SELECT relation FROM dependencies WHERE dependencies.dependent_id=tok.token_id)")
                arguments.append(rel)
        elif key == "not_outdep":
            relations = value.split("|")
            for rel in relations:
                query_where.append("? NOT IN (SELECT relation FROM dependencies WHERE dependencies.governor_id=tok.token_id)")
                arguments.append(rel)
        else:
            raise Exception("Unsupported key: %s" % key)
    query_where.append("tok.indegree>=?")
    arguments.append(graph.in_degree(v))
    query_where.append("tok.outdegree>=?")
    arguments.append(graph.out_degree(v))
    # dependency relations only support alternations, e.g. "dobj|iobj"
    # to express any object
    depcounter = 0
    for s, t, l in graph.in_edges(v, data=True):
        for key, value in l.items():
            if key == "relation":
                if value in match_all:
                    continue
                depcounter += 1
                query_from += " INNER JOIN dependencies AS o%d ON o%d.dependent_id=tok.token_id" % (depcounter, depcounter)
                relations = value.split("|")
                if len(relations) == 1:
                    query_where.append("o%d.relation=?" % depcounter)
                    arguments.append(value)
                else:
                    query_where.append("o%d.relation IN (%s)" % (depcounter, ", ".join(["?"] * len(relations))))
                    arguments.extend(relations)
            else:
                raise Exception("Unsupported key: %s" % key)
    for s, t, l in graph.out_edges(v, data=True):
        for key, value in l.items():
            if key == "relation":
                if value in match_all:
                    continue
                depcounter += 1
                query_from += " INNER JOIN dependencies AS o%d ON o%d.governor_id=tok.token_id" % (depcounter, depcounter)
                relations = value.split("|")
                if len(relations) == 1:
                    query_where.append("o%d.relation=?" % depcounter)
                    arguments.append(value)
                else:
                    query_where.append("o%d.relation IN (%s)" % (depcounter, ", ".join(["?"] * len(relations))))
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


def aggregate_sentences(c, query, query_args):
    """Aggregate sentences, returning sentence id, sentence graph, and
    sets of candidates."""
    old_sentence_id = None
    candidates = None
    old_graph = None
    for row in c.execute(query, query_args):
        sentence_id = row[0]
        graph = row[1]
        token_positions = row[2:]
        if sentence_id != old_sentence_id and old_sentence_id is not None:
            yield old_sentence_id, old_graph, candidates
            candidates = None
        if candidates is None:
            candidates = [set([t]) for t in token_positions]
        else:
            for i, t in enumerate(token_positions):
                candidates[i].add(t)
        old_sentence_id = sentence_id
        old_graph = graph
