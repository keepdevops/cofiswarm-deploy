#!/bin/bash


./cofiswarm-check-conda.sh || {
    echo "Aborting."
    exit 1
}




./brewctl down 
docker stop matrix-pgvector 2>/dev/null || true
sleep 2
docker rm matrix-pgvector 2>/dev/null || true

./brewctl check
echo "----------------------"



