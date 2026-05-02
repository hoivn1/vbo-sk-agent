# Building `vbo_sk_agent`

## Local build

```bash
bundle install
bundle exec rake build
```

Output: `build/vbo_sk_agent_v<version>.rbz`

## Release flow

1. Bump `PLUGIN_VERSION` in `vbo_sk_agent.rb`
2. Commit + push
3. Tag: `git tag v1.2.1-vbo.1 && git push --tags`
4. CI builds and attaches `.rbz` to GitHub Release automatically

## Tag convention

- `v<upstream_version>-vbo.<n>` for downstream releases of the fork
  (example: `v1.2.0-vbo.1` = fork based on upstream 1.2.0, first fork release)
- When upstream moves to 1.3.0, restart from `v1.3.0-vbo.1`
