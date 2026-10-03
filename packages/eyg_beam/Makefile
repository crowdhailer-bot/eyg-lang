# Bundle eyg_beam and its Gleam dependencies as one OTP application in ebin/.
# Mix builds a path dependency on this directory with make.
APP = {application, eyg_beam, [{description, "EYG for Erlang and Elixir hosts"}, {vsn, "0.1.0"}, {modules, Mods}, {registered, []}, {applications, [kernel, stdlib]}]}

# Rebuild when this package or the EYG packages it builds from change.
SOURCES = $(shell find src ../gleam_ir/src ../gleam_parser/src ../gleam_analysis/src ../gleam_interpreter/src -name "*.gleam")

ebin: gleam.toml manifest.toml $(SOURCES)
	gleam export erlang-shipment
	rm -rf ebin
	mkdir ebin
	cp build/erlang-shipment/*/ebin/*.beam ebin/
	erl -noshell -eval 'Mods = [list_to_atom(filename:basename(F, ".beam")) || F <- filelib:wildcard("ebin/*.beam")], ok = file:write_file("ebin/eyg_beam.app", io_lib:format("~p.~n", [$(APP)])), halt().'

clean:
	rm -rf ebin build

.PHONY: clean
