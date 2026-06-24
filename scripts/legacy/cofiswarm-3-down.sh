#!/bin/bash


./cofiswarm-check-conda.sh || {
    echo "Aborting."
    exit 1
}




./brewctl down
# RAG is serverless (sqlite-vec) now — no matrix-pgvector container to stop.

./brewctl check
echo "----------------------"



