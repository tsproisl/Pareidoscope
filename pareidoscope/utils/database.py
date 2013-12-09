#!/usr/bin/python
# -*- coding: utf-8 -*-

import operator


def get_candidates(c, nx_graph):
    """Get candidate tokens for each vertice in the graph from the
    database.
    
    Arguments:
    - `c`: Database cursor
    - `nx_graph`:

    """
    mapping = {v: i for i, v in enumerate(sorted(nx_graph.nodes()))}
    sentpos = {}
    sentences = []
    queries = [(i, _create_sql_query(nx_graph, v)) for v, i in mapping.iteritems()]
    print queries
    return {}
    for i, (query, args) in queries:
        sentpos[i] = {}
        vsents = set()
        for row in c.execute(query, args):
            sentid, position = row
            if sentid not in sentpos[i]:
                sentpos[i][sentid] = []
            sentpos[i][sentid].append(position)
            vsents.add(sentid)
        sentences.append(vsents)
    sent_intersect = reduce(lambda x, y: x.intersection(y), sentences.itervalues())
    candidates = {sentid: [sentpos[i][sentid] for i in sorted(sentpos)] for sentid in sent_intersect}
    return candidates


def _create_sql_query(nx_graph, v):
    """Create an SQL query for the given node and return a tuple
    consisting of query string and parameters.
    
    Arguments:
    - `nx_graph`:
    - `v`:

    """
    query_select = "SELECT DISTINCT tok.sentid, tok.position"
    query_from = "FROM tokens as tok INNER JOIN types as t USING (typeid)"
    query_where = []
    arguments = []
    pos_lexical = set(["word", "pos", "lemma", "wc", "root"])
    neg_lexical = set(["not_%s" % pl for pl in pos_lexical])
    for key, value in nx_graph.node[v].iteritems():
        if key in pos_lexical:
            query_where.append("t.%s=?" % key)
        elif key in neg_lexical:
            query_where.append("t.%s!=?" % key)
        elif key == "not_indep":
            query_where.append("? NOT IN (SELECT indep FROM indeps WHERE indeps.typeid=t.typeid)")
        elif key == "not_outdep":
            query_where.append("? NOT IN (SELECT indep FROM indeps WHERE indeps.typeid=t.typeid)")
        else:
            raise Exception("Unsupported key: %s" % key)
        arguments.append(value)
    query_where.append("t.indeg>=?")
    arguments.append(nx_graph.in_degree(v))
    query_where.append("t.outdeg>=?")
    arguments.append(nx_graph.out_degree(v))
    incounter = 0
    for e, l in nx_graph.in_edges(v, data=True):
        for key, value in l.iteritems():
            if key == "relation":
                incounter += 1
                query_from.append("INNER JOIN indeps AS o%d USING (typeid)" % incounter)
                query_where.append("o%d.indep=?" % incounter)
                arguments.append(value)
            else:
                raise Exception("Unsupported key: %s" % key)
    outcounter = 0
    for e, l in nx_graph.out_edges(v, data=True):
        for key, value in l.iteritems():
            if key == "relation":
                outcounter += 1
                query_from.append("INNER JOIN outdeps AS o%d USING (typeid)" % outcounter)
                query_where.append("o%d.outdep=?" % outcounter)
                arguments.append(value)
            else:
                raise Exception("Unsupported key: %s" % key)
    query = " ".join([query_select, query_from, " AND ".join(query_where)])
    return query, tuple(arguments)
