# Forking to Sous Chefs

Where it is not possible to contact the existing owner and transfer ownership to the sous-chefs, we can take over maintenance of a codebase by creating a hard fork.

**Note: Adoption**

If adopting an existing cookbook you must use the current name to carry on support for the existing user base.
In this case please see [cookbook transferring](https://github.com/sous-chefs/meta/blob/master/transfering-a-cookbook.md)

## Before you begin

A hard fork is not the friendliest approach, so we should make no other options are available. Typically, a hard fork decision will be made only after:

- sous-chefs receives a request to fork from someone willing to be primary maintainer
- verify that the cookbook is not adequately maintained
- notify the original maintainers that we’ve received a request to fork, request that they 1) resume active maintenance or 2) transfer to sous-chefs. Include a deadline to respond (the friday after 1 week)
- create a soft fork so people have a place to test and merge PRs immediately
- if the original maintainers don’t respond by the deadline, vote to fork on the day of the deadline

Sous Chefs should not make a release until we know whether we get a transfer (and keep the name) or have to do a hard fork (and affix `sc-`)

## Procedure

You should rename using the following naming schema:

- Cookbook: `mongodb` → `sc-mongodb` as per [RFC-78](https://github.com/chef/chef-rfc/blob/master/rfc078-supermarket-prefix.md)
- Repository: `sc-mongodb`

### Use of provides to maintain resource compatibility

When forking a cookbook you can use Provides to force backwards compatible resource names. As an example this would allow you to fork a cookbook `foo` with a resource `bar` and maintain `foo_bar` even though the cookbook is now named sc_foo. This would be accomplished by adding this code to the `bar` resource:

```ruby
provides :foo_bar
```

See <https://docs.chef.io/custom_resources.html#provides> for additional examples.

`Note`: This requires Chef 12 or greater, but can be done in both LWRPs and Custom Resources.
