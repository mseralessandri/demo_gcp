package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	secretspb "cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
	_ "github.com/go-sql-driver/mysql"
	"github.com/joho/godotenv"
)

var db *sql.DB
var logFile *os.File

func main() {
	// Open log file
	var err error
	logFile, err = os.OpenFile("dr_demo.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	defer logFile.Close()
	log.SetOutput(logFile)

	// Load environment variables
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using default environment variables")
	}

	// Initialize database connection
	db, err = initDB()
	if err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}
	defer db.Close()

	http.HandleFunc("/write", writeHandler)
	http.HandleFunc("/read", readHandler)
	http.HandleFunc("/web", webHandler)

	log.Println("Starting application...")
	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}

func initDB() (*sql.DB, error) {
	// Try to fetch secrets from GCP Secret Manager, otherwise use .env file
	log.Println("Connecting to the database...")
	user, password, err := getDBCredentials()
	if err != nil {
		log.Printf("Failed to get DB credentials: %v", err)
		return nil, fmt.Errorf("Failed to get DB credentials: %w", err)
	}
	host := os.Getenv("DB_HOST")
	if host == "" {
		log.Println("DB_HOST environment variable is not set")
		return nil, fmt.Errorf("DB_HOST environment variable is not set")
	}
	log.Printf("Using database host: %s", host)
	
	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/dr_demo?parseTime=true", user, password, host)
	log.Printf("Connecting to MySQL with DSN: %s:%s@tcp(%s:3306)/dr_demo?parseTime=true", user, "********", host)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Printf("Error opening database connection: %v", err)
		return nil, err
	}

	// Test the connection
	err = db.Ping()
	if err != nil {
		log.Printf("Error pinging database: %v", err)
		return db, err
	}

	log.Println("Successfully connected to the database")
	return db, nil
}

func getDBCredentials() (string, string, error) {
	log.Println("Getting database credentials...")

	ctx := context.Background()
	client, err := secretmanager.NewClient(ctx)
	if err == nil {
		defer client.Close()
		log.Println("Successfully created Secret Manager client")

		// First try to get the combined credentials secret
		projectID := "microcloud-448817" // GCP project ID
		log.Printf("Using GCP project ID: %s", projectID)

		secretName := fmt.Sprintf("projects/%s/secrets/db_credentials/versions/latest", projectID)
		log.Printf("Attempting to access secret: %s", secretName)

		resp, err := client.AccessSecretVersion(ctx, &secretspb.AccessSecretVersionRequest{Name: secretName})
		if err == nil {
			log.Println("Successfully retrieved secret from Secret Manager")

			credentials := struct {
				User     string `json:"user"`
				Password string `json:"password"`
			}{}

			if err := json.Unmarshal(resp.Payload.Data, &credentials); err == nil {
				log.Printf("Successfully unmarshaled secret data, user: %s", credentials.User)
				return credentials.User, credentials.Password, nil
			} else {
				log.Printf("Error unmarshaling secret data: %v", err)
			}
		} else {
			log.Printf("Error accessing secret: %v", err)
		}
	} else {
		log.Printf("Error creating Secret Manager client: %v", err)
	}

	// Fallback to environment variables
	log.Println("Falling back to environment variables for database credentials")

	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")

	if user == "" {
		log.Println("DB_USER environment variable is not set")
	} else {
		log.Printf("Found DB_USER in environment variables: %s", user)
	}

	if password == "" {
		log.Println("DB_PASSWORD environment variable is not set")
	} else {
		log.Println("Found DB_PASSWORD in environment variables")
	}

	if user == "" || password == "" {
		log.Println("Missing database credentials in environment variables")
		return "", "", fmt.Errorf("missing database credentials")
	}

	return user, password, nil
}

func writeHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received write request from %s", r.RemoteAddr)

	if r.Method != http.MethodPost {
		log.Printf("Invalid request method: %s", r.Method)
		http.Error(w, "Invalid request method", http.StatusMethodNotAllowed)
		return
	}

	var request struct {
		Data string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		log.Printf("Error decoding JSON: %v", err)
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if request.Data == "" {
		log.Println("Request missing data field")
		http.Error(w, "Missing data", http.StatusBadRequest)
		return
	}

	log.Printf("Processing write request with data: %s", request.Data)

	_, err := db.Exec("CREATE TABLE IF NOT EXISTS records (id INT AUTO_INCREMENT PRIMARY KEY, data TEXT)")
	if err != nil {
		log.Printf("Failed to create table: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	_, err = db.Exec("INSERT INTO records (data) VALUES (?)", request.Data)
	if err != nil {
		log.Printf("Failed to write data to database: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Write data to file
	file, err := os.OpenFile("data_backup.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Failed to open file: %v", err)
	} else {
		defer file.Close()
		logEntry := fmt.Sprintf("%s: %s\n", time.Now().Format(time.RFC3339), request.Data)
		if _, err := file.WriteString(logEntry); err != nil {
			log.Printf("Failed to write to file: %v", err)
		}
	}

	log.Printf("Data written successfully: %s", request.Data)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Data written successfully"})
}

func readHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received read request from %s", r.RemoteAddr)

	rows, err := db.Query("SELECT data FROM records")
	if err != nil {
		log.Printf("Error querying database: %v", err)
		http.Error(w, "Failed to retrieve data", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var data []string
	for rows.Next() {
		var record string
		if err := rows.Scan(&record); err == nil {
			data = append(data, record)
		} else {
			log.Printf("Error scanning row: %v", err)
		}
	}

	if err := rows.Err(); err != nil {
		log.Printf("Error iterating rows: %v", err)
	}

	log.Printf("Retrieved %d records from database", len(data))

	// Read from file
	fileData, err := os.ReadFile("data_backup.txt")
	if err != nil {
		log.Printf("Error reading backup file: %v", err)
		fileData = []byte("No file data available")
	} else {
		log.Printf("Read %d bytes from backup file", len(fileData))
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"database": data,
		"file":     string(fileData),
	})

	log.Println("Read request completed successfully")
}

func webHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received web request from %s", r.RemoteAddr)

	// Check if the web.html file exists
	_, err := os.Stat("web.html")
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Error: web.html file not found: %v", err)
			http.Error(w, "Web interface not available", http.StatusNotFound)
			return
		}
		log.Printf("Error checking web.html file: %v", err)
	}

	log.Println("Serving web.html file")
	http.ServeFile(w, r, "web.html")
	log.Println("Web request completed successfully")
}
