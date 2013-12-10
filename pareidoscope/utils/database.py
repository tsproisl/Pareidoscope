#!/usr/bin/python
# -*- coding: utf-8 -*-

import operator
import re


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
    for i, (query, args) in queries:
        print query, args
        sentpos[i] = {}
        vsents = set()
        for row in c.execute(query, args):
            sentid, position = row
            if sentid not in sentpos[i]:
                sentpos[i][sentid] = []
            sentpos[i][sentid].append(position)
            vsents.add(sentid)
        sentences.append(vsents)
    sent_intersect = reduce(lambda x, y: x.intersection(y), sentences)
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
    match_all = set([".*", ".+", "^.*$", "^.+$"])
    for key, value in nx_graph.node[v].iteritems():
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
    arguments.append(nx_graph.in_degree(v))
    query_where.append("t.outdeg>=?")
    arguments.append(nx_graph.out_degree(v))
    # dependency relations only support alternations, e.g. "dobj|iobj"
    # to express any object
    incounter = 0
    for s, t, l in nx_graph.in_edges(v, data=True):
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
    for s, t, l in nx_graph.out_edges(v, data=True):
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
