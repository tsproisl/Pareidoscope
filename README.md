# Pareidoscope #

The Pareidoscope is a collection of tools for determining the
association between arbitrary linguistic structures, e.g. between
words (collocations), between words and structures (collostructions)
or between structures. For the underlying cooccurrence model, cf.
Proisl (in preparation).


## Installation ##


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
`not_`, \eg `"not_wc": "NOUN"` for indicating that a vertex should
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

### Simple collexeme analysis ###

### Relational cooccurrences and covarying collexeme analysis ###

### Associated larger structures ###

#### Visualizing associated structures ####


