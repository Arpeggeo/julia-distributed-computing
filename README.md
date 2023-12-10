# The ultimate guide to distributed computing in Julia

In this repository we collect relevant information for people interested in distributing simple function calls on multiple cluster nodes. Although the task is simple, there are some rough (undocumented) corners in the language that inhibit even experienced users from accomplishing it currently.

We plan to update this document every now and then to reflect the latest (and cleanest) way of performing distributed computing with remote workers in Julia. If you read Julia forums, you will find many related threads where people shared solutions for specific problems, which are currently outdated. This is a central thread of discussion to solve most issues once and for all.

## Sample script

We will consider a sample script that processes a set of files in a data folder and saves the results in a results folder. We did choose this task because it involves IO and file paths, which can get tricky in remote machines:

```julia
# instantiate and precompile environment
using Pkg; Pkg.activate(@__DIR__)
Pkg.instantiate(); Pkg.precompile()

# load dependencies
using ProgressMeter
using CSV

# helper functions
function process(infile, outfile)
  # read file from disk
  csv = CSV.File(infile)

  # perform calculations
  sleep(60)

  # save new file to disk
  CSV.write(outfile, csv)
end

# MAIN SCRIPT
# -----------

# relevant directories
indir  = joinpath(@__DIR__,"data")
outdir = joinpath(@__DIR__,"results")

# files to process
infiles  = readdir(indir, join=true)
outfiles = joinpath.(outdir, basename.(infiles))
nfiles   = length(infiles)

@showprogress for i in 1:nfiles
  process(infiles[i], outfiles[i])
end
```

We follow Julia’s best practices:

1. We instantiate the environment in the host machine, which lives in the files `Project.toml` and `Manifest.toml` (the same directory of the script). Additionally, we precompile the project in case of heavy dependencies.
2. We then load the dependencies of the project, and define helper functions to be used.
3. The main work is done in a loop that calls the helper function with various files.

Let’s call this script `main.jl`. We can `cd` into the project directory and call the script as follows:

```shell
$ julia main.jl
```

## Parallelization (same machine)

Our goal is to process the files in parallel. First, we will make minor modifications to the script to be able to run it with multiple processes on the same machine (e.g. the login node). This step is important for debugging:

- We load the `Distributed` stdlib to replace the simple `for` loop by a `pmap` call. `Distributed` is always available so we don’t need to instantiate the environment before loading it.
- We wrap the preamble into *two* `@everywhere` blocks. Two separate blocks are needed so that the environment is properly instantiated in all processes before we start loading packages.
- We also add a `try-catch` to handle issues with specific files handled by different parallel processes.

Here is the resulting script after the modifications:

```julia
using Distributed

# instantiate and precompile environment in all processes
@everywhere begin
  using Pkg; Pkg.activate(@__DIR__)
  Pkg.instantiate(); Pkg.precompile()
end

# load dependencies in a *separate* @everywhere block
@everywhere begin
  # load dependencies
  using ProgressMeter
  using CSV

  # helper functions
  function process(infile, outfile)
    # read file from disk
    csv = CSV.File(infile)

    # perform calculations
    sleep(60)

    # save new file to disk
    CSV.write(outfile, csv)
  end
end

# MAIN SCRIPT
# -----------

# relevant directories
indir  = joinpath(@__DIR__,"data")
outdir = joinpath(@__DIR__,"results")

# files to process
infiles  = readdir(indir, join=true)
outfiles = joinpath.(outdir, basename.(infiles))
nfiles   = length(infiles)

status = @showprogress pmap(1:nfiles) do i
  try
    process(infiles[i], outfiles[i])
    true # success
  catch e
    false # failure
  end
end
```

Now we can execute the script with multiple processes (e.g. 4):

```shell
$ julia -p 4 main.jl
```

## Parallelization (remote machines)

Finally, we would like to run the script above in a cluster with hundreds of remote worker processes. We don’t know in advance how many processes will be available because this is the job of a job scheduler (e.g. Slurm, PBS). We have the option of using [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl) and the option to call the julia executable from a job script directly.

Suppose we are in a cluster that uses the PBS job scheduler. We can write a PBS script that calls Julia and tells it where the hosts are using the `--machine-file` option:

```shell
#!/bin/bash
#PBS -l nodes=4:ppn=12,walltime=00:05:00
#PBS -N test_julia
#PBS -q debug

julia --machine-file=$PBS_NODEFILE main.jl
```

Alternatively, suppose we are in a cluster that uses the LSF job scheduler:

```shell
#!/bin/bash
#BSUB -n 20
#BSUB -J test_julia
#BSUB -q debug

julia --machine-file=$LSB_DJOB_HOSTFILE main.jl
```

Alternatively, suppose we are in a cluster that uses the Slurm job scheduler:

```shell
#!/bin/bash
#SBATCH --job-name=test_julia
#SBATCH --ntasks=20

export SLURM_NODEFILE=`generate_pbs_nodefile`

julia --machine-file=$SLURM_NODEFILE main.jl
```
