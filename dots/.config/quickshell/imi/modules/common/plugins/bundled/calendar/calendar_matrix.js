.pragma library

// The month grid, as pure arithmetic: a Monday-first matrix of `cellCount`
// cells for the month containing (year, month), padded with the tail of
// the previous month and the head of the next. Each cell is
// { day, currentMonth, isToday }; isToday is set only when `today` (a Date)
// falls in this very month. The widget used to compute this inline on its
// visual root (tests/tst_calendar_matrix.qml pins it now).
function monthMatrix(year, month, cellCount, today) {
    var firstOfMonth = new Date(year, month, 1);
    var startOffset = (firstOfMonth.getDay() + 6) % 7; // Monday = 0
    var daysInMonth = new Date(year, month + 1, 0).getDate();
    var daysInPrevMonth = new Date(year, month, 0).getDate();
    var todayDay = (today && today.getFullYear() === year && today.getMonth() === month) ? today.getDate() : -1;

    var cells = [];
    for (var i = 0; i < startOffset; i++)
        cells.push({ day: daysInPrevMonth - startOffset + i + 1, currentMonth: false, isToday: false });
    for (var d = 1; d <= daysInMonth; d++)
        cells.push({ day: d, currentMonth: true, isToday: d === todayDay });
    var nextDay = 1;
    while (cells.length < cellCount)
        cells.push({ day: nextDay++, currentMonth: false, isToday: false });
    return cells;
}

// The first of the month `shift` months away from `now` (0 = this month).
function viewingDate(now, shift) {
    var d = new Date(now.getTime());
    d.setDate(1);
    d.setMonth(d.getMonth() + shift);
    return d;
}
