# Manage your Repositories

The aim of this script is to sync (or init) all github repositories.

Support

* **github**,
* **github entreprise**.

A repository will be accessible at `<root folder>/<site url>/<owner name>/<repository name>`

```text
<root folder>
├── github.com
│   └── rlespinasse
│       ├── repos
│       └── ...
└── github.myentreprise.com
    └── EntrepriseOrganization
        ├── SomeRepository
        ├── AnotherRepository
        └── ...
```

## Use it

### Synchronization

Run `repos.sh` to sync all repositories into `root` folder.

* Sync you current branch,
* Go to `master` branch when your branch don't exists on `origin` url,
* Run `prune`, and `gc` on each repository,
* Protect current changes (by using `stash`)

### Initialization

Run `repos.sh --init` to get all repositories into `root` folder.

## Install it

1. Create the configuration file `~/.repos.json` to configure your settings,
2. Get `repos.sh` script accessible by `PATH` environment variable.

### Configure it

Create a file `.repos.json` on your home directory

```json
{
    "root_folder": "~/sources",
    "sites": [
        {
            "site": "github.myentreprise.com",
            "api": "https://github.myentreprise.com/api/v3",
            "owner": "EntrepriseOrganization",
            "type": "orgs",
            "token": "YOUR API TOKEN from github.myentreprise.com"
        },
        {
            "site": "github.com",
            "api": "https://api.github.com",
            "owner": "YOUR LOGIN",
            "type": "users",
            "token": "YOUR API TOKEN from github.com"
        }
    ]
}
```

You can also be compliant with `golang` tree structure by setting `root_folder` value to `${GOPATH}/src` (or `~/go/src`).
