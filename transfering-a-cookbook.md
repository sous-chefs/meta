# Transferring a Cookbook to the Chef Brigade

Got a cookbook you'd like help with? We'd love to help!

## Before you begin

We need to work with the github repo owner and supermarket cookbook owner. If you aren't this person, let us know and we'll try to contact them. If necessary, fine beverages and chocolate chip cookies may be provided to encourage them to work with us.

You'll need:

- `name` - base cookbook name
- `repo_url` - code repository URL
- `supermarket_name` - Supermarket cookbook name

## Transferring the code

Cookbook code may live in a number of places, here's what to do when the code is:

### From a single-cookbook repo in GitHub

- From the `repo_url` in GitHub
- Go to the **Settings** page
- Scroll down to the **DangerZone** and click **Transfer**
- Enter the appropriate **repo name** and for the **New owner's GitHub username or organization name** enter `chef-brigade`
- Click **I understand, transfer this repository.**

### From a monolithic repo in GitHub

There's the script to extract a cookbook's history from a monolithic repo. Then upload to new repo under brigade.

- Create a GitHub repo for the cookbook with owner:`chef-brigade` and name:`${name}-cookbook`
- Clone the monolithic  to a local repo `git clone ${repo_url}`
- Extract the history of the desired cookbook from the repo: `git filter-branch --tag-name-filter cat --prune-empty --subdirectory-filter ${name} -- --all`
- Add the GitHub repo as a remote `git remote add brigade https://github.com/chef-brigade/${name}-cookbook.git`
- Push `git push brigade --all` and `git push brigade --tags`

This is adapted from “[How to extract a single file with its history from a git repository](https://gist.github.com/ssp/1663093)” by [ssp](https://github.com/ssp)

### From a non-GitHub repo
- Create a GitHub repo for the cookbook with owner:`chef-brigade` and name:`${name}-cookbook`
- Clone the cookbook to a local repo `git clone ${repo_url}`
- Add the GitHub repo as a remote `git remote add brigade https://github.com/chef-brigade/${name}-cookbook.git`
- Push `git push brigade --all` and `git push brigade --tags`

## Transferring the cookbook in Supermarket

- From the cookbook home page in Supermarket
- Click **Manage Cookbook** and select **Transfer Ownership**
- Enter `chef-brigade` and click **Transfer**


## Ensure consistent cookbook name

In case it isn't already, rename the repo to `https://github.com/chef-brigade/${name}-cookbook.git`

## Cleanup links to the old home

There are probably many references to the old URLs out there in the world. Some places to check

- Update the `README.md` with a link to the current repo and supermarket page
- 
In `metadata.rb`:
```ruby
source_url "https://github.com/chef-brigade/#{name}-cookbook" if respond_to?(:source_url)
issues_url "https://github.com/chef-brigade/#{name}-cookbook/issues" if respond_to?(:issues_url)
maintainer 'Chef Brigade'
maintainer_email 'help@chefbrigade.io'
```

