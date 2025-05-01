# Contributing

In this guide you will get an overview of the contribution workflow from opening an issue, creating a PR, reviewing, and merging the PR.

## New contributor guide

To get an overview of the project, read the [README](README.md) and [Getting Started](docs/getting_started.md).

### Issues

#### Create a new issue

If you find a bug or want to request a feature, search if an issue already exists. If a related issue doesn't exist, you can open a new issue.

For bugs please give as much information as possible.
Please include the log file (`messages.log` in the root folder where you installed/cloned the editor) if it's a bug and the commands and their outputs in case of compile errors.

#### Solve an issue

Scan through our [existing issues](https://github.com/Nimaoth/Nev/issues) to find one that interests you. You can narrow down the search using `labels` as filters.

### Make Changes

1. Fork the repository.
2. Install Nim 2.2.0
3. Create a working branch and start with your changes!
4. Make sure your changes work in the desktop/terminal version

### Pull Request

For bug fixes, tests or small obvious features/improvements (e.g. implementing more Vim Keybindings) you can directly create a pull request.
For everything else please create an issue first so we can discuss if it even makes sense to include that feature and how it should work.

When you're finished with the changes, create a pull request, also known as a PR.
- Don't forget to [link PR to issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue) if you are solving one.
- Enable the checkbox to [allow maintainer edits](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/allowing-changes-to-a-pull-request-branch-created-from-a-fork) so the branch can be updated for a merge.

Once you submit your PR, I will review your proposal. Please note that I have a full time job, and I'm only working on this in my free time, so I might take a while to get to your PR.
- As you update your PR and apply changes, mark each conversation as [resolved](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/commenting-on-a-pull-request#resolving-conversations).
- If you run into any merge issues, checkout this [git tutorial](https://github.com/skills/resolve-merge-conflicts) to help you resolve merge conflicts and other issues.
