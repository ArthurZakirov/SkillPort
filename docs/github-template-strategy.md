# GitHub Template Strategy

GitHub supports repository templates at the whole-repo level.

That means this works:

```bash
gh repo create ArthurZakirov/NewRepo --template ArthurZakirov/SomeTemplateRepo --public
```

But GitHub does not expose a native "use this subdirectory as the template" flow for `templates/agent-skill-repo`.

SkillPort keeps the generator and embedded template together because that is better for maintenance:

- `scripts/create-agent-skill-repo.sh` owns placeholder substitution.
- `templates/agent-skill-repo/` owns the starter repo structure.
- validation can happen in one toolbox repo.

If one-click GitHub template creation becomes important, publish a second minimal repo that contains only the contents of `templates/agent-skill-repo`, then mark that repo as a GitHub template:

```bash
gh repo edit ArthurZakirov/<template-repo> --template
```

Until then, use the generator script. It is more flexible than GitHub templates because it can normalize names, replace placeholders, create the starter skill directory, and optionally initialize Git.
