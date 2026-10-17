# Repository instructions

- Always commit completed feature work after running the relevant verification.
- Stage only the files and hunks that belong to the feature; leave unrelated
  worktree changes uncommitted.
- Work is done only when CI is green on its final commit. Never call a change
  "verified" or merge it into `develop` while CI is red, and never merge with
  `[skip ci]`. Intermediate commits of a larger change may be red.
- Build with the compiler pinned in `scripts/v-pin.env` (`scripts/setup-v.sh`
  builds it). `scripts/test-linux.sh` runs the Linux CI test steps locally.
- Backend-specific code goes behind the backend contract in `ui/backend.v`, and
  operating system services behind the host services in `ui/platform.v`; do
  not copy compile-time platform conditions into shared code.
