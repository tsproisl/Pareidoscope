#!/usr/bin/python
# -*- coding: utf-8 -*-

def sentences_iter(corpus):
    """Iterate over the sentences in a corpus.
    
    Arguments:
    - `corpus`:
    """
    sentence = []
    for line in corpus:
        line = line.decode("utf-8").rstrip("\n")
        if line == "</s>":
            yield sentence
        elif line.startswith("<s id="):
            sentence = []
        elif line.startswith("<"):
            pass
        else:
            sentence.append(line.split("\t"))
