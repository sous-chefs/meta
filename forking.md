# Forking to Sous Chefs

Where it is not possible to contact the existing owner and transfer ownership to the sous-chefs.

You should rename using the following naming schema:
- Cookbook: `mongodb` --> `sc_mongodb` as per [RFC-78](https://github.com/chef/chef-rfc/blob/master/rfc078-supermarket-prefix.md)
- Repository: `mongodb`


# Use of provides to maintain resource compatibility

When forking a cookbook you can use Provides to force backwards compatible resource names. As an example this would allow you to fork a cookbook `foo` with a resource `bar` and maintain `foo_bar` even though the cookbook is now named sc_foo. This would be accomplished by adding this code to the `bar` resource:

```ruby
provides :foo_bar
```

See <https://docs.chef.io/custom_resources.html#provides> for additional examples.

`Note`: This requires Chef 12 or greater, but can be done in both LWRPs and Custom Resources.

# Adoption

If adopting an existing cookbook you must use the current name to carry on support for the existing user base.
In this case please see [cookbook transferring](https://github.com/sous-chefs/meta/blob/master/transfering-a-cookbook.md)
