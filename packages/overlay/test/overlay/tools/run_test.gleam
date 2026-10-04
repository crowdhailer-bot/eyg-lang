import overlay/tools/run

pub fn report_without_output_test() {
  assert run.report([], "5") == "5"
}

pub fn report_with_output_test() {
  assert run.report(["second\n", "first"], "5")
    == "Output:\nfirstsecond\n\nResult:\n5"
}
