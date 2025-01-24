#!/bin/sh
rm -rf deps/grakn
git clone https://github.com/typedb/typedb deps/grakn
protoc -I deps/grakn --elixir_out=plugins=grpc:./lib/proto/ deps/grakn/protocol/**/*.proto
