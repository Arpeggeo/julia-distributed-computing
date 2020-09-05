# The ultimate guide to distributed computing in Julia

In this repository I would like to put together relevant information for people interested in distributing simple function calls on multiple cluster nodes. Although the task is simple, there are some rough (undocumented) corners in the language that inhibit even experienced users from accomplishing it currently.

The idea here is to update this content every now and then to reflect the latest (and cleanest) way of performing distributed computing with remote workers in Julia. If you read Julia forums, you will find many related threads where people shared solutions for specific problems, which are currently outdated. I think we need a central thread of discussion to solve most issues once and for all.

## Sample script

We will consider a sample script that processes a set of files in a data folder and saves the results in a results folder. I like this task because it involves IO and file paths, which can get tricky in remote machines:

```julia
# instantiate environment
using Pkg; Pkg.activate(@__DIR__); Pkg.instantiate()

# load dependencies
using CSV

# helper functions
function process(infile, outfile)
  # read file from disk
  csv = CSV.read(infile)

  # perform calculations
  sleep(60) # pretend it takes time
  csv.new = rand(size(csv,1))

  # save new file to disk
  CSV.write(outfile, csv)
end

# MAIN SCRIPT
# -----------

# relevant directories
indir  = "data"
outdir = "results"

# files to process
infiles  = readdir(indir, join=true)
outfiles = joinpath.(outdir, basename.(infiles))
nfiles   = length(infiles)

for i in 1:nfiles
  process(infiles[i], outfiles[i])
end
```

We follow Julia’s best practices:

1. We start by instantiating the environment in the host machine, which lives in the files Project.toml and Manifest.toml in the project directory (the same directory of the script).
2. We then load the dependencies of the project, and define helper functions to be used.
3. The main work is done in a loop that calls the helper function with various files.

Let’s call this script `main.jl`. We can cd into the project directory and call the script as follows (assuming Julia v1.4 or higher):

```shell
$ julia --project=. main.jl
```

## Parallelization (same machine)

Our goal is to process the files in parallel. First, we will make minor modifications to the script to be able to run it with multiple processes on the same machine (e.g. the login node). This step is important for debugging:

- We load the Distributed stdlib to replace the simple for loop by a pmap call. It seems that Distributed is always available so we don’t need to instantiate the environment before loading it. That will be important because we will instantiate the other dependencies in all workers with a @everywhere block call that is already available without any previous instantiation.
- We wrap the preamble into *two* @everywhere begin ... end blocks, and replace the for loop by a pmap call. We also add a `try ... catch` block to handle issues with specific files. Two separate blocks are needed so that the environment is properly instantiated in all processes before we start loading packages.

Here is the resulting script after the modifications:

```julia
using Distributed

# instantiate environment in all processes
@everywhere begin
  using Pkg; Pkg.activate(@__DIR__); Pkg.instantiate()
end

@everywhere begin
  # load dependencies
  using CSV

  # helper functions
  function process(infile, outfile)
    # read file from disk
    csv = CSV.read(infile)

    # perform calculations
    sleep(60) # pretend it takes time
    csv.new = rand(size(csv,1))

    # save new file to disk
    CSV.write(outfile, csv)
  end
end

# MAIN SCRIPT
# -----------

# relevant directories
indir  = "data"
outdir = "results"

# files to process
infiles  = readdir(indir, join=true)
outfiles = joinpath.(outdir, basename.(infiles))
nfiles   = length(infiles)

status = pmap(1:nfiles) do i
  try
    process(infiles[i], outfiles[i])
    true # success
  catch e
    @warn "failed to process $(infiles[i])"
    false # failure
  end
end
```

Now we can execute the script with multiple processes (e.g. 4):

```shell
$ julia -p 4 --project=. main.jl
```

## IO issues

Notice that we used "data" and "results" as our file paths in the script. If we try to run the script from outside the project directory (e.g. proj), we will get an error:

```shell
$ julia --project=proj proj/main.jl
ERROR: LoadError: SystemError: unable to read directory data: No such file or directory
```

Even worse, these file paths may not exist on different machines when we request multiple remote workers. To solve this, we need to use paths relative to the `main.jl` source:

```julia
# relevant directories
indir  = joinpath(@__DIR__,"data")
outdir = joinpath(@__DIR__,"results")
```

or set these paths in the command line using some package like [DocOpt.jl](https://github.com/docopt/DocOpt.jl).

Our previous command should work with the suggested modifications:

```shell
$ julia --project=proj proj/main.jl
```

## Parallelization (remote machines)

Finally, we would like to run the script above in a cluster with hundreds of remote worker processes. We don’t know in advance how many processes will be available because this is the job of a job scheduler (e.g. SLURM, PBS). We have the option of using [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl) and the option to call the julia executable from a job script directly.

Suppose we are in a cluster that uses the PBS job scheduler. We can write a PBS script that calls Julia and tells it where the hosts are using the `--machine-file` option:

```shell
#!/bin/bash
#PBS -l nodes=4:ppn=12,walltime=00:05:00
#PBS -N test_julia
#PBS -q debug

julia --machinefile=$PBS_NODEFILE main.jl
```

# Contributors

@juliohm @samuel_okon @pfitzseb
