# Performance Benchmarks for gRPCServer.jl
#
# Usage:
#   julia --project=benchmark benchmark/benchmarks.jl [category] [--save filename] [--compare filename]
#
# Categories:
#   dispatch       - Request dispatch latency benchmarks
#   streaming      - Server streaming throughput benchmarks
#   serialization  - Message serialization benchmarks
#   (no argument)  - Run all benchmarks
#
# Examples:
#   julia --project=benchmark benchmark/benchmarks.jl
#   julia --project=benchmark benchmark/benchmarks.jl serialization
#   julia --project=benchmark benchmark/benchmarks.jl --save baseline.json
#   julia --project=benchmark benchmark/benchmarks.jl --compare baseline.json

using BenchmarkTools
using gRPCServer
using Printf

# Import individual benchmark categories
include("dispatch.jl")
include("streaming.jl")
include("serialization.jl")

# Color codes for terminal output
const RESET = "\e[0m"
const GREEN = "\e[32m"
const RED = "\e[31m"
const YELLOW = "\e[33m"
const BOLD = "\e[1m"

"""
    create_benchmark_suite() -> BenchmarkGroup

Create the complete benchmark suite with all categories.
"""
function create_benchmark_suite()
    suite = BenchmarkGroup()
    suite["dispatch"] = create_dispatch_benchmarks()
    suite["streaming"] = create_streaming_benchmarks()
    suite["serialization"] = create_serialization_benchmarks()
    return suite
end

"""
    format_time(t::Float64) -> String

Format a time value in appropriate units.
"""
function format_time(t::Float64)
    if t < 1e-6
        return @sprintf("%.3f ns", t * 1e9)
    elseif t < 1e-3
        return @sprintf("%.3f μs", t * 1e6)
    elseif t < 1
        return @sprintf("%.3f ms", t * 1e3)
    else
        return @sprintf("%.3f s", t)
    end
end

"""
    format_memory(bytes::Int) -> String

Format memory in appropriate units.
"""
function format_memory(bytes::Int)
    if bytes < 1024
        return "$bytes bytes"
    elseif bytes < 1024^2
        return @sprintf("%.2f KiB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.2f MiB", bytes / 1024^2)
    else
        return @sprintf("%.2f GiB", bytes / 1024^3)
    end
end

"""
    print_benchmark_result(name::String, trial::BenchmarkTools.Trial; indent::Int=0)

Print a formatted benchmark result.
"""
function print_benchmark_result(name::String, trial::BenchmarkTools.Trial; indent::Int=0)
    prefix = "  " ^ indent
    med = median(trial)

    time_str = format_time(med.time / 1e9)
    mem_str = format_memory(med.memory)
    allocs = med.allocs

    println("$(prefix)$(BOLD)$(name)$(RESET)")
    println("$(prefix)  Time:   $(time_str)")
    println("$(prefix)  Memory: $(mem_str)")
    println("$(prefix)  Allocs: $(allocs)")
end

"""
    print_benchmark_group(name::String, group::BenchmarkGroup; indent::Int=0)

Print a benchmark group recursively.
"""
function print_benchmark_group(name::String, group::BenchmarkGroup; indent::Int=0)
    prefix = "  " ^ indent
    println("\n$(prefix)$(BOLD)$(name)$(RESET)")
    println("$(prefix)$("─" ^ 50)")

    for (key, value) in sort(collect(group), by=x->string(x[1]))
        if value isa BenchmarkGroup
            print_benchmark_group(string(key), value; indent=indent+1)
        elseif value isa BenchmarkTools.Trial
            print_benchmark_result(string(key), value; indent=indent+1)
        end
    end
end

"""
    print_results(results::BenchmarkGroup)

Print human-readable benchmark results.
"""
function print_results(results::BenchmarkGroup)
    println("\n$(BOLD)gRPCServer.jl Benchmark Results$(RESET)")
    println("=" ^ 60)

    for (name, group) in sort(collect(results), by=x->string(x[1]))
        if group isa BenchmarkGroup
            print_benchmark_group(string(name), group)
        end
    end

    println("\n" * "=" ^ 60)
end

"""
    print_comparison(baseline::BenchmarkGroup, current::BenchmarkGroup)

Print comparison between baseline and current results.
"""
function print_comparison(baseline::BenchmarkGroup, current::BenchmarkGroup)
    println("\n$(BOLD)Benchmark Comparison$(RESET)")
    println("=" ^ 70)

    judgment = judge(median(current), median(baseline))

    for (category, category_judgment) in sort(collect(judgment), by=x->string(x[1]))
        if !(category_judgment isa BenchmarkGroup)
            continue
        end

        println("\n$(BOLD)$(category)$(RESET)")
        println("-" ^ 70)

        for (name, bench_judgment) in sort(collect(category_judgment), by=x->string(x[1]))
            if !(bench_judgment isa BenchmarkTools.TrialJudgement)
                continue
            end

            # Get ratio
            ratio = bench_judgment.ratio
            time_ratio = ratio.time

            # Calculate percentage change
            pct = (time_ratio - 1.0) * 100

            # Determine color based on change
            if pct < -5
                color = GREEN
                indicator = "↓"
            elseif pct > 20
                color = RED
                indicator = "↑ REGRESSION"
            elseif pct > 5
                color = YELLOW
                indicator = "↑"
            else
                color = RESET
                indicator = "~"
            end

            # Format output
            sign = pct >= 0 ? "+" : ""
            println("  $(name): $(color)$(sign)$(round(pct, digits=1))% $(indicator)$(RESET)")
        end
    end

    println("\n" * "=" ^ 70)
    println("Legend: $(GREEN)↓ improvement$(RESET), $(YELLOW)↑ slower$(RESET), $(RED)↑ REGRESSION (>20%)$(RESET), ~ within noise")
end

"""
    save_results(results::BenchmarkGroup, filename::String)

Save benchmark results to a JSON file.
"""
function save_results(results::BenchmarkGroup, filename::String)
    BenchmarkTools.save(filename, results)
    println("Results saved to: $(filename)")
end

"""
    load_results(filename::String) -> BenchmarkGroup

Load benchmark results from a JSON file.
"""
function load_results(filename::String)
    if !isfile(filename)
        error("Baseline file not found: $(filename)")
    end
    return BenchmarkTools.load(filename)[1]
end

"""
    parse_args(args) -> NamedTuple

Parse command line arguments.
"""
function parse_args(args)
    category = nothing
    save_file = nothing
    compare_file = nothing

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--save" && i < length(args)
            save_file = args[i + 1]
            i += 2
        elseif arg == "--compare" && i < length(args)
            compare_file = args[i + 1]
            i += 2
        elseif !startswith(arg, "-")
            if arg in ("dispatch", "streaming", "serialization")
                category = arg
            else
                println("Unknown category: $(arg)")
                println("Valid categories: dispatch, streaming, serialization")
                exit(1)
            end
            i += 1
        else
            println("Unknown option: $(arg)")
            exit(1)
        end
    end

    return (category=category, save_file=save_file, compare_file=compare_file)
end

"""
    run_benchmarks(; category=nothing)

Run benchmarks and return results.
"""
function run_benchmarks(; category=nothing)
    println("Creating benchmark suite...")
    suite = create_benchmark_suite()

    if category !== nothing
        println("Running $(category) benchmarks...")
        if !haskey(suite, category)
            error("Unknown category: $(category)")
        end
        suite_to_run = BenchmarkGroup()
        suite_to_run[category] = suite[category]
    else
        println("Running all benchmarks...")
        suite_to_run = suite
    end

    # Tune and run benchmarks
    println("Tuning benchmarks (this may take a moment)...")
    tune!(suite_to_run)

    println("Running benchmarks...")
    results = run(suite_to_run)

    return results
end

# Main entry point
function main()
    args = parse_args(ARGS)

    # Run benchmarks
    results = run_benchmarks(; category=args.category)

    # Print results
    print_results(results)

    # Save if requested
    if args.save_file !== nothing
        save_results(results, args.save_file)
    end

    # Compare if requested
    if args.compare_file !== nothing
        println("\nLoading baseline from: $(args.compare_file)")
        baseline = load_results(args.compare_file)
        print_comparison(baseline, results)
    end
end

# Run main if this is the entry point
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
