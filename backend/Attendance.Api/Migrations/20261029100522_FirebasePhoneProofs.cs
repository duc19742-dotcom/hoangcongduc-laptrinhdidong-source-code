using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Attendance.Api.Migrations
{
    /// <inheritdoc />
    public partial class FirebasePhoneProofs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ExternalChallengeExpiresAtUtc",
                table: "AuthFlows",
                type: "datetimeoffset",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ExternalChallengeId",
                table: "AuthFlows",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ExternalChallengeStartedAtUtc",
                table: "AuthFlows",
                type: "datetimeoffset",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ExternalVerificationAttempts",
                table: "AuthFlows",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "ExternalAuthProofs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    UserId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Provider = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    ProofHash = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    SubjectDigest = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    AuthenticatedAtUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    CreatedAtUtc = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    RowVersion = table.Column<byte[]>(type: "rowversion", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ExternalAuthProofs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ExternalAuthProofs_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ExternalAuthProofs_ProofHash",
                table: "ExternalAuthProofs",
                column: "ProofHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ExternalAuthProofs_UserId",
                table: "ExternalAuthProofs",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ExternalAuthProofs");

            migrationBuilder.DropColumn(
                name: "ExternalChallengeExpiresAtUtc",
                table: "AuthFlows");

            migrationBuilder.DropColumn(
                name: "ExternalChallengeId",
                table: "AuthFlows");

            migrationBuilder.DropColumn(
                name: "ExternalChallengeStartedAtUtc",
                table: "AuthFlows");

            migrationBuilder.DropColumn(
                name: "ExternalVerificationAttempts",
                table: "AuthFlows");
        }
    }
}
