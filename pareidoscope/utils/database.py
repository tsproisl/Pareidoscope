#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import functools
import re
import sqlite3


def create_db(filename):
    """Connect to database, create tables and indexes and return
    connection and cursor."""
    conn = sqlite3.connect(filename)
    c = conn.cursor()
    c.execute("PRAGMA page_size=4096")
    c.execute("PRAGMA cache_size=100000")
    c.execute("CREATE TABLE sentences (sentence_id INTEGER PRIMARY KEY AUTOINCREMENT, original_id TEXT, graph TEXT, UNIQUE (original_id))")
    c.execute("CREATE TABLE tokens (token_id INTEGER PRIMARY KEY AUTOINCREMENT, sentence_id INTEGER, position INTEGER, word TEXT, pos TEXT, lemma TEXT, wc TEXT, indegree INTEGER, outdegree INTEGER, root BOOLEAN, FOREIGN KEY (sentence_id) REFERENCES sentences (sentence_id), UNIQUE (sentence_id, position))")
    c.execute("CREATE TABLE dependencies (governor_id INTEGER, dependent_id INTEGER, relation TEXT, FOREIGN KEY (governor_id) REFERENCES tokens (token_id), FOREIGN KEY (dependent_id) REFERENCES tokens (token_id), UNIQUE (governor_id, dependent_id))")
    c.execute("CREATE INDEX word_idx ON tokens (word)")
    c.execute("CREATE INDEX pos_idx ON tokens (pos)")
    c.execute("CREATE INDEX lemma_idx ON tokens (lemma)")
    c.execute("CREATE INDEX wc_idx ON tokens (wc)")
    c.execute("CREATE INDEX indegree_idx ON tokens (indegree)")
    c.execute("CREATE INDEX outdegree_idx ON tokens (outdegree)")
    c.execute("CREATE INDEX root_idx ON tokens (root)")
    c.execute("CREATE INDEX governor_id_relation_idx ON dependencies (governor_id, relation)")
    c.execute("CREATE INDEX dependent_id_relation_idx ON dependencies (dependent_id, relation)")
    c.execute("CREATE INDEX relation_idx ON dependencies (relation)")
    return conn, c


def insert_sentence(c, origid, gs, graph):
    """Insert sentence into database"""
    c.execute("INSERT INTO sentences (original_id, graph) VALUES (?, ?)", (origid, graph))
    sid = c.execute("SELECT sentence_id FROM sentences WHERE original_id = ?", (origid, )).fetchall()[0][0]
    token_id = {}
    for vertice in sorted(gs.nodes()):
        word = gs.nodes[vertice]["word"]
        pos = gs.nodes[vertice]["pos"]
        lemma = gs.nodes[vertice]["lemma"]
        wc = gs.nodes[vertice]["wc"]
        root = "root" in gs.nodes[vertice] and gs.nodes[vertice]["root"] == "root"
        c.execute("INSERT INTO tokens (sentence_id, position, word, pos, lemma, wc, indegree, outdegree, root) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", (sid, vertice, word, pos, lemma, wc, gs.in_degree(vertice), gs.out_degree(vertice), root))
        token_id[vertice] = c.execute("SELECT token_id FROM tokens WHERE sentence_id = ? AND position = ?", (sid, vertice)).fetchall()[0][0]
    for s, t, l in gs.edges(data=True):
        c.execute("INSERT INTO dependencies (governor_id, dependent_id, relation) VALUES (?, ?, ?)", (token_id[s], token_id[t], l["relation"]))


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
        indegree = g.in_degree[vertex]
        outdegree = g.out_degree[vertex]
        if indegree > 0:
            where.append("indegree >= ?")
            args.append(indegree)
        if outdegree > 0:
            where.append("outdegree >= ?")
            args.append(outdegree)
        for k, v in g.nodes[vertex].items():
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
    candidate_sentences = (r[0] for r in c.execute("SELECT graph FROM sentences WHERE sentence_id IN (%s)" % ", ".join([str(_) for _ in candidate_ids])))
    return candidate_sentences


def regexp(expression, item):
    """Does expression match item?

    Arguments:
    - `expression`:
    - `item`:

    """
    reg = re.compile(expression)
    return reg.search(item) is not None


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
        indegree = query_graph.in_degree[vertex]
        outdegree = query_graph.out_degree[vertex]
        if indegree > 0:
            where.append("tok_%s.indegree >= %d" % (vertex, indegree))
        if outdegree > 0:
            where.append("tok_%s.outdegree >= %d" % (vertex, outdegree))
        for k, v in query_graph.nodes[vertex].items():
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


# Only used in pareidoscope_collexeme_analysis_db
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
