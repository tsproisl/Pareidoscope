#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re


def sentences_iter(corpus, return_id=False):
    """Iterate over the sentences in a corpus in CoNLL-U format
    (http://universaldependencies.org/format.html).

    Arguments:
    - `corpus`:

    """
    pattern = re.compile(r"^#\s*sent_id\s*=\s*(\S.*)$")
    origid = ""
    sentence = []
    for line in corpus:
        line = line.rstrip()
        if line == "":
            if return_id:
                yield sentence, origid
            else:
                yield sentence
            sentence = []
        elif line.startswith("#") and len(sentence) == 0:
            m = re.search(pattern, line)
            if m:
                origid = m.group(1)
        else:
            sentence.append(line.split("\t"))
