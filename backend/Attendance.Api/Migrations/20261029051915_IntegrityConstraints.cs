using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Attendance.Api.Migrations
{
    /// <inheritdoc />
    public partial class IntegrityConstraints : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddCheckConstraint(
                name: "CK_Shift_Grace",
                table: "Shifts",
                sql: "[LateGraceMinutes] BETWEEN 0 AND 120");

            migrationBuilder.CreateIndex(
                name: "IX_QrSessions_CreatedByUserId",
                table: "QrSessions",
                column: "CreatedByUserId");

            migrationBuilder.AddCheckConstraint(
                name: "CK_QR_Expiry",
                table: "QrSessions",
                sql: "[ExpiresAtUtc] > [CreatedAtUtc]");

            migrationBuilder.AddCheckConstraint(
                name: "CK_OTP_Attempts",
                table: "OtpChallenges",
                sql: "[FailedAttempts] BETWEEN 0 AND 5 AND [ExpiresAtUtc] > [CreatedAtUtc]");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_ActorUserId",
                table: "AuditLogs",
                column: "ActorUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRequests_ReviewedByUserId",
                table: "AttendanceRequests",
                column: "ReviewedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRequestEvents_ActorUserId",
                table: "AttendanceRequestEvents",
                column: "ActorUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRecords_ApprovedRequestId",
                table: "AttendanceRecords",
                column: "ApprovedRequestId");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Record_Action",
                table: "AttendanceRecords",
                sql: "[Action] IN ('CheckIn','CheckOut')");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Attempt_Action",
                table: "AttendanceAttempts",
                sql: "[Action] IN ('CheckIn','CheckOut')");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Attempt_Outcome",
                table: "AttendanceAttempts",
                sql: "[Outcome] IN ('Accepted','NeedsReview')");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Attempt_Position",
                table: "AttendanceAttempts",
                sql: "[Latitude] BETWEEN -90 AND 90 AND [Longitude] BETWEEN -180 AND 180 AND [AccuracyMeters] > 0 AND [DistanceMeters] >= 0");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceRecords_AttendanceRequests_ApprovedRequestId",
                table: "AttendanceRecords",
                column: "ApprovedRequestId",
                principalTable: "AttendanceRequests",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceRequestEvents_Users_ActorUserId",
                table: "AttendanceRequestEvents",
                column: "ActorUserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceRequests_Users_ReviewedByUserId",
                table: "AttendanceRequests",
                column: "ReviewedByUserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AuditLogs_Users_ActorUserId",
                table: "AuditLogs",
                column: "ActorUserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_OtpChallenges_Users_UserId",
                table: "OtpChallenges",
                column: "UserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_QrSessions_Users_CreatedByUserId",
                table: "QrSessions",
                column: "CreatedByUserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceRecords_AttendanceRequests_ApprovedRequestId",
                table: "AttendanceRecords");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceRequestEvents_Users_ActorUserId",
                table: "AttendanceRequestEvents");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceRequests_Users_ReviewedByUserId",
                table: "AttendanceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_AuditLogs_Users_ActorUserId",
                table: "AuditLogs");

            migrationBuilder.DropForeignKey(
                name: "FK_OtpChallenges_Users_UserId",
                table: "OtpChallenges");

            migrationBuilder.DropForeignKey(
                name: "FK_QrSessions_Users_CreatedByUserId",
                table: "QrSessions");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Shift_Grace",
                table: "Shifts");

            migrationBuilder.DropIndex(
                name: "IX_QrSessions_CreatedByUserId",
                table: "QrSessions");

            migrationBuilder.DropCheckConstraint(
                name: "CK_QR_Expiry",
                table: "QrSessions");

            migrationBuilder.DropCheckConstraint(
                name: "CK_OTP_Attempts",
                table: "OtpChallenges");

            migrationBuilder.DropIndex(
                name: "IX_AuditLogs_ActorUserId",
                table: "AuditLogs");

            migrationBuilder.DropIndex(
                name: "IX_AttendanceRequests_ReviewedByUserId",
                table: "AttendanceRequests");

            migrationBuilder.DropIndex(
                name: "IX_AttendanceRequestEvents_ActorUserId",
                table: "AttendanceRequestEvents");

            migrationBuilder.DropIndex(
                name: "IX_AttendanceRecords_ApprovedRequestId",
                table: "AttendanceRecords");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Record_Action",
                table: "AttendanceRecords");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Attempt_Action",
                table: "AttendanceAttempts");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Attempt_Outcome",
                table: "AttendanceAttempts");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Attempt_Position",
                table: "AttendanceAttempts");
        }
    }
}
