#!/bin/bash

# For now we bootstrap the ansible virtual env using the system python3.

# Keep ansible virtual env separate from any existing conda virtual env.
for i in $(seq ${CONDA_SHLVL:-0})
do
    conda deactivate
done

# Keep ansible virtual env separate from any existing non-conda virtual env.
if [ "$(type -t deactivate)" == "function" ]
then
    deactivate
fi

# Make directory to hold virtual environment
mkdir -p venv

if [ ! -e venv/netboot_admin ]
then
    # Create virtual environment in venv subdir.
    # Use sub-shell to avoid having to cd back.
    (cd venv && python3 -m venv netboot_admin)
fi

if [ ! -e activate ]
then
    # Create activate symlink for convenience
    ln -s venv/netboot_admin/bin/activate
fi

# Update .gitignore
touch .gitignore
for f in /venv/ /activate
do
    grep -q "^$f\\$" .gitignore || echo "$f" >> .gitignore
done

# Activate virtual env and install ansible
source activate
python3 -m pip install ansible

# Create ansible.cfg if it doesdn't exist
if [ ! -e ansible.cfg ]
then
    # Make sure not to use hashed path to ansible-config
    hash -r
    ansible-config init --disabled | sed 's/^;inventory=.*/inventory=hosts.yml/' > ansible.cfg
fi
