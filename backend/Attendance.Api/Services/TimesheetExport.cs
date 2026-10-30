using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Xml.Linq;

namespace Attendance.Api.Services;

// Small, typed Open XML workbook; inline strings cannot be interpreted as formulas.
// No spreadsheet engine/dependency needed for two data-only sheets.
public static class TimesheetExport
{
    private static readonly XNamespace Ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    public static byte[] Create(IReadOnlyList<EmployeeTimesheet> sheets, string status, int revision, string filter)
    {
        var summary = new List<object?[]> {
            new object?[] { "BẢNG CÔNG", status, "Phiên bản", revision },
            new object?[] { "Bộ lọc", filter, "Xuất lúc (giờ Việt Nam)", DateTimeOffset.UtcNow.ToOffset(TimeSpan.FromHours(7)).DateTime },
            new object?[] { "Mã NV", "Nhân viên", "Phòng ban", "Năm", "Tháng", "Số ca", "Ngày có lịch", "Ngày có vào", "Giờ làm xác nhận", "Giờ nghỉ phép", "Ca thiếu công", "Ca trễ", "Ca về sớm" }
        };
        var details = new List<object?[]> { new object?[] { "Mã NV", "Nhân viên", "Ngày ca", "Ca", "Địa điểm", "Bắt đầu", "Kết thúc", "Vào", "Ra", "Phút làm xác nhận", "Phút nghỉ phép", "Phút trễ", "Phút về sớm", "Trạng thái", "Nguồn vào", "Nguồn ra" } };
        foreach (var s in sheets)
        {
            summary.Add([s.EmployeeCode, s.EmployeeName, s.Department, s.Year, s.Month, s.ScheduledShifts, s.ScheduledDays, s.AttendedDays, s.ConfirmedHours, s.LeaveHours, s.MissingShifts, s.LateShifts, s.EarlyShifts]);
            foreach (var l in s.Lines) details.Add([s.EmployeeCode, s.EmployeeName, l.Date.ToDateTime(TimeOnly.MinValue), l.Shift, l.Location,
                Local(l.StartUtc), Local(l.EndUtc), Local(l.CheckInUtc), Local(l.CheckOutUtc), l.WorkedMinutes, l.LeaveMinutes, l.LateMinutes, l.EarlyMinutes, Status(l.Status), l.InSource, l.OutSource]);
        }
        using var stream = new MemoryStream();
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Create, true))
        {
            Write(zip, "[Content_Types].xml", """
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
                """);
            Write(zip, "_rels/.rels", """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
                """);
            Write(zip, "xl/workbook.xml", """
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Tổng hợp" sheetId="1" r:id="rId1"/><sheet name="Chi tiết" sheetId="2" r:id="rId2"/></sheets></workbook>
                """);
            Write(zip, "xl/_rels/workbook.xml.rels", """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
                """);
            Write(zip, "xl/styles.xml", """
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="22" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
                """);
            Sheet(zip, "xl/worksheets/sheet1.xml", summary); Sheet(zip, "xl/worksheets/sheet2.xml", details);
        }
        return stream.ToArray();
    }
    private static DateTime? Local(DateTimeOffset? time) => time?.ToOffset(TimeSpan.FromHours(7)).DateTime;
    public static string Status(string s) => s switch { "MissingCheckIn" => "Thiếu lượt vào", "MissingCheckOut" => "Thiếu lượt ra", "Scheduled" => "Chưa đến giờ", "Working" => "Đang trong ca", "Completed" => "Đủ vào/ra", "Leave" => "Nghỉ phép", "LeaveConflict" => "Xung đột nghỉ phép/công", _ => s };
    private static void Sheet(ZipArchive zip, string path, List<object?[]> rows)
    {
        var data = new XElement(Ns + "sheetData");
        for (var r = 0; r < rows.Count; r++)
        {
            var row = new XElement(Ns + "row", new XAttribute("r", r + 1));
            for (var c = 0; c < rows[r].Length; c++)
            {
                var value = rows[r][c]; if (value is null) continue;
                var cell = new XElement(Ns + "c", new XAttribute("r", Column(c) + (r + 1)));
                if (value is DateTime date) { cell.Add(new XAttribute("s", 1), new XElement(Ns + "v", date.ToOADate().ToString(CultureInfo.InvariantCulture))); }
                else if (value is int or double or decimal) cell.Add(new XElement(Ns + "v", Convert.ToString(value, CultureInfo.InvariantCulture)));
                else cell.Add(new XAttribute("t", "inlineStr"), new XElement(Ns + "is", new XElement(Ns + "t", new XAttribute(XNamespace.Xml + "space", "preserve"), Clean(value.ToString()!))));
                row.Add(cell);
            }
            data.Add(row);
        }
        var sheet = new XElement(Ns + "worksheet", new XElement(Ns + "sheetViews", new XElement(Ns + "sheetView", new XAttribute("workbookViewId", 0), new XElement(Ns + "pane", new XAttribute("ySplit", 1), new XAttribute("topLeftCell", "A2"), new XAttribute("state", "frozen")))),
            new XElement(Ns + "cols", new XElement(Ns + "col", new XAttribute("min", 1), new XAttribute("max", 16), new XAttribute("width", 23), new XAttribute("customWidth", 1))), data);
        Write(zip, path, sheet.ToString(SaveOptions.DisableFormatting));
    }
    private static string Clean(string value) => new(value.Where(c => !char.IsControl(c) || c is '\n' or '\r' or '\t').ToArray());
    private static string Column(int i) { var s = ""; do { s = (char)('A' + i % 26) + s; i = i / 26 - 1; } while (i >= 0); return s; }
    private static void Write(ZipArchive zip, string path, string xml) { using var writer = new StreamWriter(zip.CreateEntry(path).Open(), new UTF8Encoding(false)); writer.Write(xml); }
}
