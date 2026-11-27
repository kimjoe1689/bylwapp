package metrics

import "testing"

func TestRQ1StaysNotEvaluableWithoutRows(t *testing.T) {
	report := SummarizeRQ1(nil, nil)
	if report.DeliveryRate.Status != "not_evaluable" || report.AckRate.Status != "not_evaluable" {
		t.Fatalf("%+v", report)
	}
}

func TestRQ1AndRQ2UseOnlyObservedRows(t *testing.T) {
	events := []EventView{
		{DeviceID: "phone-1", MeasurementType: "reminder", MonotonicUS: 2, Values: map[string]any{"schedule_id": "med-1", "disposition": "ACK_TIMELY"}},
		{DeviceID: "phone-1", MeasurementType: "reminder", MonotonicUS: 1, Values: map[string]any{"schedule_id": "med-1", "disposition": "COMMAND_LOGGED"}},
		{DeviceID: "phone-1", MeasurementType: "worn_state", MonotonicUS: 3, Values: map[string]any{"match_key": "w1", "worn": true}},
	}
	ledger := []LedgerRow{
		{DeviceID: "phone-1", MatchKey: "med-1", ReferenceType: "reminder_eligible", ReferenceValue: "true"},
		{DeviceID: "phone-1", MatchKey: "med-1", ReferenceType: "reminder_perceived", ReferenceValue: "true"},
		{DeviceID: "phone-1", MatchKey: "w1", ReferenceType: "worn", ReferenceValue: "true"},
		{DeviceID: "phone-1", MatchKey: "missing", ReferenceType: "worn", ReferenceValue: "false"},
	}
	rq1 := SummarizeRQ1(events, ledger)
	if rq1.DeviceJournal["ack_timely"] != 1 || rq1.AckRate.Status != "computed" || rq1.DeliveryRate.Num != 1 || rq1.DeliveryRate.Den != 1 {
		t.Fatalf("%+v", rq1)
	}
	rq2 := SummarizeRQ2(events, ledger)
	if rq2.Counts["tp"] != 1 || rq2.Unmatched != 1 {
		t.Fatalf("%+v", rq2)
	}
}

func TestSUSRequiresEveryItem(t *testing.T) {
	partial := SummarizeRQ4([]EventView{{DeviceID: "p", MeasurementType: "sus", Values: map[string]any{"q1": 5}}})
	if partial.SUS[0].Status != "not_evaluable" {
		t.Fatal(partial.SUS[0])
	}
	values := map[string]any{}
	for i := 1; i <= 10; i++ {
		values["q"+itoa(i)] = 5
	}
	full := SummarizeRQ4([]EventView{{DeviceID: "p", MeasurementType: "sus", Values: values}})
	if full.SUS[0].Status != "computed" || full.SUS[0].Score == nil || *full.SUS[0].Score != 50 {
		t.Fatalf("%+v", full.SUS[0])
	}
}

func TestRQ3DoesNotInventLoss(t *testing.T) {
	report := SummarizeRQ3(0, 0, 0)
	if report.DuplicateRate.Status != "not_evaluable" || report.PendingOnServer != "not_observable" {
		t.Fatalf("%+v", report)
	}
}
