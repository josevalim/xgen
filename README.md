# xgen

When v0.13 was released, we outlined the next steps regarding integrating Elixir and Mix with OTP. The outlined steps were:

1. Integrate applications configuration (provided by OTP) right into Mix;
2. Provide an Elixir logger that knows how to print and format Elixir exceptions and stacktraces;
3. Properly expose the functionality provided by Applications, Supervisors, GenServers and GenEvents and study how they can integrate with Elixir. For example, how to consume events from GenEvent as a stream of data?
4. Study how patterns like tasks and agents can be integrated into the language, often picking up the lessons learned by libraries like e2 and functionality exposed by OTP itself;
5. Rewrite the Mix and ExUnit guides to focus on applications and OTP as a whole, rebranding it to "Building Apps with Mix and OTP";

The goal of this project is to explore steps `3` and `4` before their eventual inclusion in Elixir source.

This README provides installation instructions and the overall description of the main modules provided by this library.

## Installation

This project requires Elixir v0.13.0 forward. To install it, just add it to your `deps`:

    def deps do
      [{:xgen, github: "josevalim/xgen"}]
    end

And list it as a runtime dependency for your application:

    def application do
      [applications: [:xgen]]
    end

Run `mix deps.get` and you are good to go.

## GenServer

...

## GenEvent

...

## Supervisor

...

## Application

...

## GenTask

...

## Agent

...

## License

This project is released under the same LICENSE and Copyright as Elixir.
