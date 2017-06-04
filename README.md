# Pareidoscope #

The Pareidoscope is a collection of tools for determining the
association between arbitrary linguistic structures, e.g. between
words (collocations), between words and structures (collostructions)
or between larger linguistic structures. For the underlying
cooccurrence model, cf. Proisl (in preparation).


## Installation ##

The Pareidoscope is available on
[PyPI](https://pypi.python.org/pypi/Pareidoscope) and can be installed
using pip:

    pip3 install Pareidoscope

Alternatively, you can download and decompress the
[latest release](https://github.com/tsproisl/Pareidoscope/releases/latest)
or clone the git repository:

    git clone https://github.com/tsproisl/Pareidoscope.git

In the new directory, run the following command:

    python3 setup.py install


## Usage ##

### Input formats ###

#### Corpora ####

Corpora can be provided in two different formats: In CoNLL-U format or
in CWB-treebank format.

CoNLL-U is the format used for the treebanks of the
[Universal Dependencies project](http://universaldependencies.org/)
([Nivre et al., 2016](http://www.lrec-conf.org/proceedings/lrec2016/pdf/348_Paper.pdf)).
The format is specified in the
[UD documentation](http://universaldependencies.org/format.html). Here
is an example that has been adapted from the documentation:

    1    They     they    PRON    PRP    _    2    nsubj    2:nsubj|4:nsubj    _
    2    buy      buy     VERB    VBP    _    0    root     0:root             _
    3    and      and     CONJ    CC     _    4    cc       4:cc               _
    4    sell     sell    VERB    VBP    _    2    conj     0:root|2:conj      _
    5    books    book    NOUN    NNS    _    2    obj      2:obj|4:obj        _
    6    .        .       PUNCT   .      _    2    punct    2:punct            _

There are ten tab-separated columns. The first five columns are for
the word ID, the word form, the lemma, the universal part-of-speech
tag and a language-specific part-of-speech tag. Columns six and ten,
which are empty in this example, are for morphological features and
miscellaneous annotation. In columns seven to nine, the dependency
analysis of this sentence is encoded. Columns seven and eight encode
the basic dependencies which are required to form a tree. Column seven
indicates the ID of the governor, column eight the type of the
dependency relation between the governor and the current word. In
column nine, an enhanced dependency graph can be represented that does
not need to be a tree.

For details on the CWB-treebank format, cf.
[Proisl and Uhrig (2012)](http://www.lrec-conf.org/proceedings/lrec2012/pdf/709_Paper.pdf).


#### Queries ####

The query graphs can be provided as JSON serializations of the
node-link format understood by [NetworkX](https://networkx.github.io/)
([Hagberg et al., 2008](https://conference.scipy.org/proceedings/scipy2008/paper_2/full_text.pdf)).
All command-line tools can operate on multiple queries, therefore a
list of queries has to be provided, even for a single query. Here is
an example of a one-element list containing the query graph for
finding associated larger structures of monotransitive uses of the
verb *give* with `pareidoscope_associated_structures` (more example
queries are provided in the `doc` directory):

    [
        {
            "graph": {
                "description": "Monotransitive uses of the verb give"
            },
            "nodes": [
                {
                    "id": 0,
                    "wc": "VERB",
                    "lemma": "give",
                    "focus_point": true,
                    "not_outdep": ["iobj", "obl"]
                },
                {
                    "id": 1
                }
            ],
            "links": [
                {
                    "source": 0,
                    "target": 1,
                    "relation": "obj"
                }
            ]
        }
    ]

Queries are represented as dictionaries with two obligatory keys:
`nodes` for the vertices and `links` for the edges. Under the key
`graph`, additional information such as a description of the query can
be stored. Both the vertices and the edges of the query graph are
represented as lists of dictionaries. An edge is specified by the IDs
of its source and target vertices and, optionally, by the kind of
dependency relation. The vertices are required to have an ID and can
have other, optional attributes.

The attributes that can be used for the vertices depend on the kind of
query. The following attributes can always be used: `word`, `pos`,
`lemma`, `wc`, `root`, `not_indep` (a list), `not_outdep` (a list).
The first five attributes can also be negated by prefixing them with
`not_`, e.g. `"not_wc": "NOUN"` for indicating that a vertex should
not be a noun.

For determining the association strength between two structures with
`pareidoscope_association_strength`, the following additional
attributes can be used. The attribute `query` has to be used for every
vertex and takes the values `A`, `B` or `AB`. This attribute indicates
if the vertex belongs to *G<sub>A</sub>*, *G<sub>B</sub>* or to both,
i.e. to *G<sub>C</sub>*. For vertices marked as `"query": "AB"`, the
optional attributes `only_A` and `only_B` can be used. These
attributes are lists and indicate which other attributes only apply to
*G<sub>A</sub>* or to *G<sub>B</sub>*. The focus point vertex of the
graph can be marked by setting `"focus_point": true`. The attributes
`only_A` and `only_B` can also be used for edges.

For simple collexeme analysis with `pareidoscope_collexeme_analysis`,
the attribute `collo_item` has to be set to `true` for the collexeme
vertex. This vertex is automatically the focus point.

For relational cooccurrences and covarying collexeme analysis with
`pareidoscope_covarying_collexemes`, the attributes `collo_A`,
`collo_B` have to be set to `true` for the two collexeme vertices.
The attribute `focus_point` can be used to mark the focus point
vertex.

For finding associated larger structures with
`pareidoscope_associated_structures`, the focus point vertex can be
marked by setting `"focus_point": true`.


### Convert a corpus into an SQLite3 database ###

For most of the programs described below, it is necessary to convert
your corpus into an SQLite3 database. This can considerably speed up
highly selective queries; for very general queries that require that
almost every sentence in the corpus is checked, this makes less of a
difference.

Corpora in CoNNL-U or CWB-treebank format can be converted to an
SQLite3 database using `pareidoscope_corpus_to_sqlite`. Running the
program with the option `-h` outputs a help message with detailed
usage information. Here is an example where we convert the training
part of the
[English Universal Dependencies treebank](https://github.com/UniversalDependencies/UD_English)
(`en-ud-train.conllu`; we use the version included in the
[2.0 release of the UD treebanks](http://hdl.handle.net/11234/1-1983).)
which is in CoNLL-U format, and create the database `en-ud-train.db`:

    pareidoscope_corpus_to_sqlite --db en-ud-train.db --format conllu en-ud-train.conllu


### Association between two linguistic structures ###

The program `pareidoscope_association_strength` determines the
association strength between two linguistic structures.

Here is a sample query for the cooccurrence of the ditransitive with
direct objects that have a determiner (this query and other queries
can be found in the query file `ex_association_two_structures.json`):

    [
        {
            "graph": {
                "description": "cooccurrence of the ditransitive with direct
                                objects that have a determiner"
            },
            "nodes": [
                {
                    "id": 0,
                    "wc": "VERB",
                    "query": "AB",
                    "focus_point": true
                },
                {
                    "id": 1,
                    "query": "A"
                },
                {
                    "id": 2,
                    "wc": "NOUN",
                    "query": "AB"
                },
                {
                    "id": 3,
                    "query": "B"
                }
            ],
            "links": [
                {
                    "source": 0,
                    "target": 1,
                    "relation": "iobj"
                },
                {
                    "source": 0,
                    "target": 2,
                    "relation": "obj"
                },
                {
                    "source": 2,
                    "target": 3,
                    "relation": "det"
                }
            ]
        }
    ]

The verb the and direct object are part of both linguistic structures
and are therefore marked as `AB`. The indirect object only belongs to
the ditransitive and is marked as `A`, the determiner only belongs to
the other linguistic structure and is marked as `B`. Additionally, the
verb is marked as the focus point vertex.

Here is an example for invoking the program (use the option `-h` for
detailed usage information):

    pareidoscope_association_strength --format db -o associations en-ud-train.db ex_association_two_structures.json

In this example, we run the queries specified in
`ex_association_two_structures.json` on the corpus converted above.
Option `--format db` indicates that we operate on an SQLite3 database
(this program can also operate directly on corpus files in CoNLL-U or
CWB-treebank format). The results are written to `associations.tsv` in
a tab-separated format and contain, for every query and every counting
method, the frequencies *O<sub>11</sub>*, *R<sub>1</sub>*,
*C<sub>1</sub>* and *N*, the number of inconsistencies and three
association measures (log-likelihood, *t*-score, Dice coefficient).


### Simple collexeme analysis ###

The program `pareidoscope_collexeme_analysis` performs a simple
collexeme analysis, i.e. it determines the association strength
between a linguistic structure and the word forms or lemmata that
occur in a given slot of that structure. To this end, the collo item
vertex has to be marked with `"collo_item": true` in the query. Here
is an example query (taken from the query file
`ex_collexeme_analysis.json`) that finds verbs that are associated
with the ditransitive:

    [
        {
            "graph": {
                "description": "Verbs associated with the ditransitive"
            },
            "nodes": [
                {
                    "id": 0,
                    "wc": "VERB",
                    "collo_item": true
                },
                {
                    "id": 1
                },
                {
                    "id": 2
                }
            ],
            "links": [
                {
                    "source": 0,
                    "target": 1,
                    "relation": "iobj"
                },
                {
                    "source": 0,
                    "target": 2,
                    "relation": "obj"
                }
            ]
        }
    ]

Here is an example for invoking the program (use the option `-h` for
detailed usage information):

    pareidoscope_collexeme_analysis -o collexemes en-ud-train.db ex_collexeme_analysis.json

In this example, we run the queries specified in
`ex_collexeme_analysis.json` on the corpus converted above. The
program takes an optional option `-c` where we can specify if the
collo items should be word forms or lemmata (the latter is the
default).

The results are written to `collexemes.tsv` in a tab-separated format
and contain, for every query and cooccurring lemma, the frequencies
*O<sub>11</sub>*, *R<sub>1</sub>*, *C<sub>1</sub>* and *N* and three
association measures (log-likelihood, *t*-score, Dice coefficient).
For simple collexeme analysis, three of the four counting methods are
fully equivalent. Since counting sentences does not make much sense in
this case because of the large number of inconsistencies that can be
expected, we do not include that counting method. As a consequence, we
do not need to distinguish between different counting methods and do
not need to include a field for inconsistencies. The results are
ordered by log-likelihood.


### Relational cooccurrences and covarying collexeme analysis ###

The program `pareidoscope_covarying_collexemes` performs a covarying
collexeme analysis which, for linguistic structures that consist of a
single dependency relation, is equivalent to analyzing relational
cooccurrences. The program determines the association between the word
forms or lemmata that cooccur in two slots of a linguistic structure.
To this end, the two slots have to be marked with `"collo_A": true`
and `"collo_B": true` in the query. Here is an example query (taken
from the query file `ex_covarying_collexemes.json`) that determines
the association between the verbs in the *into*-causative:

    [
        {
            "graph": {
                "description": "Into-causative, i.e. verb someone into verbing"
            },
            "nodes": [
                {
                    "id": 0,
                    "wc": "VERB",
                    "collo_A": true
                },
                {
                    "id": 1,
                    "pos": "VBG",
                    "collo_B": true
                },
                {
                    "id": 2
                },
                {
                    "id": 3,
                    "lemma": "into"
                }
            ],
            "links": [
                {
                    "source": 0,
                    "target": 1,
                    "relation": "advcl"
                },
                {
                    "source": 0,
                    "target": 2,
                    "relation": "obj"
                },
                {
                    "source": 1,
                    "target": 3,
                    "relation": "mark"
                }
            ]
        }
    ]

Here is an example for invoking the program (use the option `-h` for
detailed usage information):

    pareidoscope_covarying_collexemes -o covarying en-ud-train.db ex_covarying_collexemes.json

In this example, we run the queries specified in
`ex_covarying_collexemes.json` on the corpus converted above. The
program takes an optional option `-c` where we can specify if the
cooccurring items should be word forms or lemmata (the latter is the
default).

The results are written to `covarying.tsv` in a tab-separated format
and contain, for every query, cooccurring pair of items and counting
method, the frequencies *O<sub>11</sub>*, *R<sub>1</sub>*,
*C<sub>1</sub>* and *N*, the number of inconsistencies and three
association measures (log-likelihood, *t*-score, Dice coefficient).
The results are ordered by log-likelihood for counting focus points.


### Associated larger structures ###

The program `pareidoscope_associated_structures` determines which
larger delexicalized linguistic structures are associated with the
query structure. It considers all star-like larger structures, i.e.
structures where all new vertices have to be adjacent to a query
vertex, that cooccur with the query structury in at least
`--min-coocc` sentences (default: 5) and have a maximum of
`--max-size` vertices (default: 7). The vertices of the larger
structures are delexicalized and contain only word class information
(the `wc` attribute). Here is an example query that looks for larger
structures that are associated with monotransitive uses of the verb
*give*:

    [
        {
            "graph": {
                "description": "Monotransitive uses of the verb give"
            },
            "nodes": [
                {
                    "id": 0,
                    "wc": "VERB",
                    "lemma": "give",
                    "focus_point": true,
                    "not_outdep": ["iobj", "obl"]
                },
                {
                    "id": 1
                }
            ],
            "links": [
                {
                    "source": 0,
                    "target": 1,
                    "relation": "obj"
                }
            ]
        }
    ]

Here is an example for invoking the program (use the option `-h` for
detailed usage information):

    pareidoscope_associated_structures -o assoc_struc en-ud-train.db ex_associated_structures.json

In this example, we run the queries specified in
`ex_associated_structures.json` on the corpus converted above.

The results are written to `assoc_struc.tsv` in a tab-separated format
and contain, for every query, associated larger structure and counting
method, the frequencies *O<sub>11</sub>*, *R<sub>1</sub>*,
*C<sub>1</sub>* and *N*, the number of inconsistencies and three
association measures (log-likelihood, *t*-score, Dice coefficient).
The results are ordered by log-likelihood for counting focus points.


#### Visualizing associated structures ####

The associated larger structures output by
`pareidoscope_associated_structures` are in the same node-link format
as the query graphs and can be visualized with the program
`pareidoscope_draw_graphs`. Note that this requires that Graphviz and
the Python package PyDotPlus are installed on your computer.

Here is an example for invoking the program (use the option `-h` for
detailed usage information):

    tail -n +2 assoc_struc.tsv | head | cut -f2 | pareidoscope_draw_graphs -o draw -

In this example, we use the output file created by the previous
command, extract the ten most strongly associated larger structures
(using GNU coreutils) and draw them. The images are written to the
directory `draw`. Here are the visualizations created for the four
larger structures that are most strongly associated with
monotransitive *give*.

![Rank 1](doc/monotransitive_give_01.png?raw=true)
![Rank 2](doc/monotransitive_give_02.png?raw=true)
![Rank 3](doc/monotransitive_give_03.png?raw=true)
![Rank 4](doc/monotransitive_give_04.png?raw=true)
