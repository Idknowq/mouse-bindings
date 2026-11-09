#!/bin/zsh
set -eu
cd "${0:A:h}"
swift build -c release
task_bin_dir=$(swift build -c release --show-bin-path)
task_app="$PWD/dist/MouseBindings.app"
mkdir -p "$task_app/Contents/MacOS"
cp "$task_bin_dir/MouseBindings" "$task_app/Contents/MacOS/MouseBindings"
cp Info.plist "$task_app/Contents/Info.plist"
# Developer signing keeps the designated requirement stable across rebuilds.
# Ad-hoc signing binds Accessibility approval to each binary's changing hash.
task_signer=${SIGN_ID:-$(security find-identity -v -p codesigning | awk '/Apple Development:/ { print $2; exit }')}
task_signer=${task_signer:--}
codesign --force --sign "$task_signer" "$task_app"
codesign --verify --strict "$task_app"
if [[ "$task_signer" == "-" ]]; then
    echo "Ad-hoc signed: Accessibility approval may need renewal after each rebuild."
fi
echo "Built $task_app"
