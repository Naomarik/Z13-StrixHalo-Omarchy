# Hyprland Quick Reference

## Check config errors
```bash
hyprctl configerrors
```

## View rolling log
```bash
hyprctl rollinglog
```

## Window rule syntax (0.53+)
- `windowrulev2` is deprecated, use `windowrule`
- Anonymous: `windowrule = match:class .*, border_size 0, match:workspace w[1]`
- Named block:
  ```
  windowrule {
      name = my-rule
      match:class = some-app
      float = on
  }
  ```
- Workspace selectors: `w[N]` = window count, `m[monitor]` = monitor, `s[bool]` = special
