#!/bin/bash
# Script to run the test server

cd "$(dirname "$0")"
exec julia --project=. test_server.jl
