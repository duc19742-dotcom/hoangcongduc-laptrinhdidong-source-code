using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Attendance.Api.Migrations
{
    /// <inheritdoc />
    public partial class ManualCheckoutEvidence : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_AttendanceRecords_AttemptId",
                table: "AttendanceRecords");

            migrationBuilder.AlterColumn<Guid>(
                name: "AttemptId",
                table: "AttendanceRecords",
                type: "uniqueidentifier",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRecords_AttemptId",
                table: "AttendanceRecords",
                column: "AttemptId",
                unique: true,
                filter: "[AttemptId] IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_AttendanceRecords_AttemptId",
                table: "AttendanceRecords");

            migrationBuilder.AlterColumn<Guid>(
                name: "AttemptId",
                table: "AttendanceRecords",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier",
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRecords_AttemptId",
                table: "AttendanceRecords",
                column: "AttemptId",
                unique: true);
        }
    }
}
