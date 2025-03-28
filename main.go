package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
	_ "github.com/go-sql-driver/mysql"  // Importa il driver MySQL (con _ per evitare l'uso diretto)
	//_ "github.com/lib/pq" // Import PostgreSQL driver



)

var db *sql.DB
var logFile *os.File

func main() {
	// Open log file for writing
	var err error
	logFile, err = os.OpenFile("dr_demo.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	defer logFile.Close()
	log.SetOutput(logFile)

	log.Println("Starting application...")

	http.HandleFunc("/write", writeHandler)
	http.HandleFunc("/read", readHandler)
	http.HandleFunc("/web", webHandler)

	// For HTTP:
	log.Fatal(http.ListenAndServe(":8080", nil))

	// For HTTPS (if you have a valid SSL certificate and key):
	//log.Fatal(http.ListenAndServeTLS(":443", "path/to/cert.crt", "path/to/cert.key", nil))
}

func writeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Invalid request method", http.StatusMethodNotAllowed)
		return
	}

	data := r.FormValue("data")
	if data == "" {
		http.Error(w, "Missing data", http.StatusBadRequest)
		return
	}

	// Write to database first
	dbUser := "dr_demo_user"
	dbPassword := "dr_demo_password"
	dbHost := "localhost"
	dbName := "dr_demo"

	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/%s?parseTime=true", dbUser, dbPassword, dbHost, dbName)
	//dsn := fmt.Sprintf("postgres://%s:%s@%s/%s?sslmode=disable", dbUser, dbPassword, dbHost, dbName)

	log.Printf("DSN: %s", dsn)
	var err error
	db, err = sql.Open("mysql", dsn)
	//db, err = sql.Open("postgres", dsn)
	if err != nil {
		
		log.Printf("Failed to connect to database: %v", err)
		return
	}
	defer db.Close()

	_, err = db.Exec("CREATE TABLE IF NOT EXISTS records (id INT AUTO_INCREMENT PRIMARY KEY, data TEXT)")
	//_, err = db.Exec("CREATE TABLE IF NOT EXISTS dr_demo.records (id SERIAL PRIMARY KEY, data TEXT)")
	if err != nil {
		log.Printf("Failed to create table: %v", err)
		return
	}

	_, err = db.Exec("INSERT INTO records (data) VALUES (?)", data)
	//_, err = db.Exec("INSERT INTO dr_demo.records (data) VALUES ($1)", data)
	if err != nil {
		log.Printf("Failed to write data to database: %v", err)
		return
	}

	log.Printf("Data written to database successf:qully: %s", data)

	// Read back from database and write to disk
	var retrievedData string
	err = db.QueryRow("SELECT data FROM dr_demo.records ORDER BY id DESC LIMIT 1").Scan(&retrievedData)
	if err != nil {
		log.Printf("Failed to retrieve data from database: %v", err)
		return
	}

	file, err := os.OpenFile("data_backup.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		http.Error(w, "Failed to write to disk", http.StatusInternalServerError)
		log.Printf("Failed to write to disk: %v", err)
		return
	}
	defer file.Close()

	logEntry := fmt.Sprintf("%s: %s\n", time.Now().Format(time.RFC3339), retrievedData)
	if _, err := file.WriteString(logEntry); err != nil {
		log.Printf("Failed to write log entry to disk: %v", err)
	}

	log.Printf("Data written to disk successfully: %s", retrievedData)
	fmt.Fprintln(w, "Data written successfully")

}

func readHandler(w http.ResponseWriter, r *http.Request) {
	dbUser := "dr_demo_user"
	dbPassword := "dr_demo_password"
	dbHost := "localhost"
	dbName := "dr_demo"

	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/%s?parseTime=true", dbUser, dbPassword, dbHost, dbName)
	//dsn := fmt.Sprintf("postgres://%s:%s@%s/%s?sslmode=disable", dbUser, dbPassword, dbHost, dbName)
	db, err := sql.Open("mysql", dsn)
	//db, err := sql.Open("postgres", dsn)
	if err != nil {
		http.Error(w, "Failed to connect to database", http.StatusInternalServerError)
		log.Printf("Failed to connect to database: %v", err)
		return
	}
	defer db.Close()

	var lastData string
	err = db.QueryRow("SELECT data FROM dr_demo.records ORDER BY id DESC LIMIT 1").Scan(&lastData)
	if err != nil {
		log.Printf("Failed to retrieve data from database: %v", err)
		lastData = "No data available"
	}

	fileData, err := os.ReadFile("data_backup.txt")
	if err != nil {
		fileData = []byte("No file data available")
	}

	fmt.Fprintf(w, "Last stored data (DB): %s\nLast stored data (File):\n%s", lastData, string(fileData))
}

func webHandler(w http.ResponseWriter, r *http.Request) {
	html := `
	<!DOCTYPE html>
	<html>
	<head>
		<title>Disaster Recovery Demo</title>
	</head>
	<body>
		<h1>Disaster Recovery Demo</h1>
		<form action="/write" method="post">
			<label>Enter Data:</label>
			<input type="text" name="data">
			<input type="submit" value="Save">
		</form>
		<h2>Stored Data</h2>
		<pre id="dataOutput">Loading...</pre>
		<script>
			function fetchData() {
				fetch('/read')
					.then(response => response.text())
					.then(data => document.getElementById('dataOutput').innerText = data);
			}
			setInterval(fetchData, 3000);
			fetchData();
		</script>
	</body>
	</html>
	`
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprintln(w, html)
}
