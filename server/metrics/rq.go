// Package metrics computes Chapter 3-style summaries from stored rows.
// A zero denominator is reported as not_evaluable. These functions never fill
// in rates that were not observed.
package metrics

import "time"

type Rate struct {
	Status string   `json:"status"`
	Value  *float64 `json:"value"`
	Num    int      `json:"numerator"`
	Den    int      `json:"denominator"`
	Reason string   `json:"reason,omitempty"`
}

func ratio(num, den int, emptyReason string) Rate {
	if den == 0 {
		return Rate{Status: "not_evaluable", Num: num, Den: 0, Reason: emptyReason}
	}
	value := float64(num) / float64(den)
	return Rate{Status: "computed", Value: &value, Num: num, Den: den}
}

type EventView struct {
	DeviceID        string
	MeasurementType string
	MonotonicUS     int64
	Wall            *time.Time
	Values          map[string]any
}

type LedgerRow struct {
	DeviceID       string
	MatchKey       string
	ReferenceType  string
	ReferenceValue string
}

type RQ1 struct {
	Note          string         `json:"note"`
	DeviceJournal map[string]int `json:"device_journal"`
	Observer      map[string]int `json:"observer_ledger"`
	AckRate       Rate           `json:"device_ack_rate"`
	MissRate      Rate           `json:"device_miss_rate"`
	DeliveryRate  Rate           `json:"observer_delivery_rate"`
}

func SummarizeRQ1(events []EventView, ledger []LedgerRow) RQ1 {
	counts := map[string]int{
		"scheduled": 0, "command_logged": 0, "ack_timely": 0, "ack_delayed": 0, "missed": 0, "censored": 0,
	}
	latest := map[string]EventView{}
	for _, event := range events {
		if event.MeasurementType != "reminder" {
			continue
		}
		key := str(event.Values["schedule_id"])
		if key == "" {
			key = str(event.Values["match_key"])
		}
		if key == "" {
			continue
		}
		prev, ok := latest[key]
		if !ok || event.MonotonicUS >= prev.MonotonicUS {
			latest[key] = event
		}
	}
	for _, event := range latest {
		switch str(event.Values["disposition"]) {
		case "SCHEDULED":
			counts["scheduled"]++
		case "COMMAND_LOGGED":
			counts["command_logged"]++
		case "ACK_TIMELY":
			counts["ack_timely"]++
		case "ACK_DELAYED":
			counts["ack_delayed"]++
		case "MISSED":
			counts["missed"]++
		case "CENSORED":
			counts["censored"]++
		}
	}
	acked := counts["ack_timely"] + counts["ack_delayed"]
	fired := counts["command_logged"] + acked + counts["missed"] + counts["censored"]
	observerEligible := 0
	observerPerceived := 0
	for _, row := range ledger {
		if row.ReferenceType == "reminder_eligible" && truthy(row.ReferenceValue) {
			observerEligible++
		}
		if row.ReferenceType == "reminder_perceived" && truthy(row.ReferenceValue) {
			observerPerceived++
		}
	}
	return RQ1{
		Note:          "Device-journal rates use reminder events only. Observer delivery rate stays not_evaluable until an independent ledger has eligible rows. Empty output is not a measured zero performance.",
		DeviceJournal: counts,
		Observer:      map[string]int{"eligible": observerEligible, "perceived": observerPerceived},
		AckRate:       ratio(acked, fired, "no fired reminder instances in the device journal"),
		MissRate:      ratio(counts["missed"], fired, "no fired reminder instances in the device journal"),
		DeliveryRate:  ratio(observerPerceived, observerEligible, "no observer-marked eligible reminders"),
	}
}

type RQ2 struct {
	Note        string         `json:"note"`
	Counts      map[string]int `json:"confusion"`
	Unmatched   int            `json:"unmatched_ground_truth"`
	Recall      Rate           `json:"recall"`
	Specificity Rate           `json:"specificity"`
}

func SummarizeRQ2(events []EventView, ledger []LedgerRow) RQ2 {
	index := map[string]EventView{}
	for _, event := range events {
		key := event.DeviceID + "|" + str(event.Values["match_key"]) + "|" + family(event.MeasurementType)
		if str(event.Values["match_key"]) == "" {
			continue
		}
		prev, ok := index[key]
		if !ok || event.MonotonicUS >= prev.MonotonicUS {
			index[key] = event
		}
	}
	tp, tn, fp, fn, unmatched := 0, 0, 0, 0, 0
	for _, row := range ledger {
		if row.ReferenceType != "worn" && row.ReferenceType != "data_gap" && row.ReferenceType != "care_attention" {
			continue
		}
		event, ok := index[row.DeviceID+"|"+row.MatchKey+"|"+row.ReferenceType]
		if !ok {
			unmatched++
			continue
		}
		got := positiveEvent(event)
		want := truthy(row.ReferenceValue)
		switch {
		case want && got:
			tp++
		case !want && !got:
			tn++
		case !want && got:
			fp++
		default:
			fn++
		}
	}
	return RQ2{
		Note:        "Confusion counts exist only for ground-truth rows that share device_id and match_key with a device event. Unmatched rows are not treated as errors.",
		Counts:      map[string]int{"tp": tp, "tn": tn, "fp": fp, "fn": fn},
		Unmatched:   unmatched,
		Recall:      ratio(tp, tp+fn, "no positive matched ground-truth rows"),
		Specificity: ratio(tn, tn+fp, "no negative matched ground-truth rows"),
	}
}

type RQ3 struct {
	Note            string `json:"note"`
	StoredEvents    int    `json:"stored_events"`
	DuplicateAcks   int    `json:"duplicate_acks"`
	Conflicts       int    `json:"conflicts"`
	DuplicateRate   Rate   `json:"duplicate_attempt_rate"`
	PendingOnServer string `json:"pending_on_server"`
}

func SummarizeRQ3(stored, duplicates, conflicts int) RQ3 {
	attempts := stored + duplicates + conflicts
	return RQ3{
		Note:            "Counts are server ingest attempts. Pending events that never left the phone are not visible here. This is not a data-loss estimate.",
		StoredEvents:    stored,
		DuplicateAcks:   duplicates,
		Conflicts:       conflicts,
		DuplicateRate:   ratio(duplicates, attempts, "no ingest attempts"),
		PendingOnServer: "not_observable",
	}
}

type RQ4 struct {
	Note  string         `json:"note"`
	Tasks map[string]int `json:"task_dispositions"`
	SUS   []SUSResult    `json:"sus"`
}

type SUSResult struct {
	DeviceID string   `json:"device_id"`
	MatchKey string   `json:"match_key"`
	Score    *float64 `json:"score"`
	Status   string   `json:"status"`
	Reason   string   `json:"reason,omitempty"`
}

func SummarizeRQ4(events []EventView) RQ4 {
	tasks := map[string]int{"unassisted": 0, "assisted": 0, "abandoned": 0, "not_started": 0}
	var scores []SUSResult
	for _, event := range events {
		if event.MeasurementType == "usability_task" {
			switch str(event.Values["disposition"]) {
			case "unassisted", "assisted", "abandoned", "not_started":
				tasks[str(event.Values["disposition"])]++
			}
		}
		if event.MeasurementType == "sus" {
			scores = append(scores, scoreSUS(event))
		}
	}
	if scores == nil {
		scores = []SUSResult{}
	}
	return RQ4{
		Note:  "SUS is scored only when q1 through q10 are all present. A missing item does not become a total. Task counts are logged dispositions, not a completed ethics study.",
		Tasks: tasks,
		SUS:   scores,
	}
}

func scoreSUS(event EventView) SUSResult {
	result := SUSResult{DeviceID: event.DeviceID, MatchKey: str(event.Values["match_key"]), Status: "not_evaluable"}
	sum := 0
	for i := 1; i <= 10; i++ {
		raw, ok := event.Values["q"+itoa(i)]
		if !ok {
			result.Reason = "missing item"
			return result
		}
		n := int(asFloat(raw))
		if n < 1 || n > 5 {
			result.Reason = "item outside 1..5"
			return result
		}
		if i%2 == 1 {
			sum += n - 1
		} else {
			sum += 5 - n
		}
	}
	score := 2.5 * float64(sum)
	result.Score = &score
	result.Status = "computed"
	return result
}

func family(measurementType string) string {
	switch measurementType {
	case "worn_state":
		return "worn"
	case "data_gap":
		return "data_gap"
	case "care_attention":
		return "care_attention"
	default:
		return measurementType
	}
}

func positiveEvent(event EventView) bool {
	switch event.MeasurementType {
	case "worn_state":
		return truthyValue(event.Values["worn"])
	case "data_gap":
		return truthyValue(event.Values["gap"])
	case "care_attention":
		return str(event.Values["flag"]) == "CARE_ATTENTION_OVERDUE"
	default:
		return false
	}
}

func truthy(value string) bool {
	return value == "true" || value == "1" || value == "yes" || value == "perceived"
}

func truthyValue(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		return truthy(typed)
	default:
		return false
	}
}

func str(value any) string {
	text, _ := value.(string)
	return text
}

func asFloat(value any) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case int:
		return float64(typed)
	case int64:
		return float64(typed)
	default:
		return 0
	}
}

func itoa(n int) string {
	if n == 10 {
		return "10"
	}
	return string(rune('0' + n))
}
