using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Attendance.Api.Migrations
{
    /// <inheritdoc />
    public partial class GpsAttendanceAndRememberedDevices : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_QrRedemptions_QrSessionId_EmployeeId",
                table: "QrRedemptions");

            migrationBuilder.AlterColumn<Guid>(
                name: "QrSessionId",
                table: "QrRedemptions",
                type: "uniqueidentifier",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier");

            migrationBuilder.AlterColumn<Guid>(
                name: "QrSessionId",
                table: "AttendanceAttempts",
                type: "uniqueidentifier",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier");

            migrationBuilder.CreateTable(
                name: "RememberedDevices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    UserId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TokenHash = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    ExpiresAtUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    RevokedAtUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true),
                    CreatedAtUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    RowVersion = table.Column<byte[]>(type: "rowversion", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RememberedDevices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RememberedDevices_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_QrRedemptions_QrSessionId_EmployeeId",
                table: "QrRedemptions",
                columns: new[] { "QrSessionId", "EmployeeId" },
                unique: true,
                filter: "[QrSessionId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_RememberedDevices_TokenHash",
                table: "RememberedDevices",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RememberedDevices_UserId",
                table: "RememberedDevices",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RememberedDevices");

            migrationBuilder.DropIndex(
                name: "IX_QrRedemptions_QrSessionId_EmployeeId",
                table: "QrRedemptions");

            migrationBuilder.AlterColumn<Guid>(
                name: "QrSessionId",
                table: "QrRedemptions",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier",
                oldNullable: true);

            migrationBuilder.AlterColumn<Guid>(
                name: "QrSessionId",
                table: "AttendanceAttempts",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier",
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_QrRedemptions_QrSessionId_EmployeeId",
                table: "QrRedemptions",
                columns: new[] { "QrSessionId", "EmployeeId" },
                unique: true);
        }
    }
}
