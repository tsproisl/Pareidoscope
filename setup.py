from distutils.core import setup

setup(
    name='Pareidoscope',
    version='0.1.0',
    author='Thomas Proisl',
    author_email='thomas.proisl@fau.de',
    packages=['pareidoscope','pareidoscope.utils'],
    # scripts=['bin/foo.py',],
    # url='http://pypi.python.org/pypi/Pareidoscope/',
    license='GNU General Public License (GPL) 3.0',
    description='A tool for determining the association between arbitrary linguistic structures.',
    long_description=open('README.txt').read(),
    install_requires=[
        "networkx >= 1.6",
    ],
)
