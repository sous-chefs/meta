# Transferring a Cookbook to the Chef Brigade

Got a cookbook you'd like help with? We'd love to help!

## Before you begin

We need to work with the github repo owner and supermarket cookbook owner. If you aren't this person, let us know and we'll try to contact them. If necessary, fine beverages and chocolate chip cookies may be provided to encourage them to work with us.

When this is not possible please see [forking](https://github.com/sous-chefs/meta/blob/master/forking.md)

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
- Enter the appropriate **repo name** and for the **New owner's GitHub username or organization name** enter `sous-chefs`
- Click **I understand, transfer this repository.**

### From a monolithic repo in GitHub

There's the script to extract a cookbook's history from a monolithic repo. Then upload to new repo under sous-chefs.

- Create a GitHub repo for the cookbook with owner:`sous-chefs` and name:`${name}`
- Clone the monolithic  to a local repo `git clone ${repo_url}`
- Extract the history of the desired cookbook from the repo: `git filter-branch --tag-name-filter cat --prune-empty --subdirectory-filter ${name} -- --all`
- Add the GitHub repo as a remote `git remote add sous-chefs https://github.com/sous-chefs/${name}.git`
- Push `git push sous-chefs --all` and `git push sous-chefs --tags`

This is adapted from “[How to extract a single file with its history from a git repository](https://gist.github.com/ssp/1663093)” by [ssp](https://github.com/ssp)

### From a non-GitHub repo
- Create a GitHub repo for the cookbook with owner:`sous-chefs` and name:`${name}`
- Clone the cookbook to a local repo `git clone ${repo_url}`
- Add the GitHub repo as a remote `git remote add sous-chefs https://github.com/sous-chefs/${name}.git`
- Push `git push sous-chefs --all` and `git push sous-chefs --tags`

## Transferring the cookbook in Supermarket

- From the cookbook home page in Supermarket
- Click **Manage Cookbook** and select **Transfer Ownership**
- Enter `sous-chefs` and click **Transfer**


## Ensure consistent cookbook name

In case it isn't already, rename the repo to `https://github.com/sous-chefs/${name}.git`

## Cleanup links to the old home

There are probably many references to the old URLs out there in the world. Some places to check

- Update the `README.md` with a link to the current repo and supermarket page
-
In `metadata.rb`:
```ruby
source_url "https://github.com/sous-chefs/#{name}" if respond_to?(:source_url)
issues_url "https://github.com/sous-chefs/#{name}/issues" if respond_to?(:issues_url)
maintainer 'Sous Chefs'
maintainer_email 'help@chefsous-chefs.io'
```
