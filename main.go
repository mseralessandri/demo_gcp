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
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func initDB() (*sql.DB, error) {
	// Try to fetch secrets from GCP Secret Manager, otherwise use .env file
	log.Println("Connecting to the database...")
	user, password, err := getDBCredentials()
	if err != nil {
		return nil, fmt.Errorf("failed to get DB credentials: %w", err)
	}
	host := os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/dr_demo?parseTime=true", user, password, host)
	return sql.Open("mysql", dsn)
}

func getDBCredentials() (string, string, error) {
	ctx := context.Background()
	client, err := secretmanager.NewClient(ctx)
	if err == nil {
		defer client.Close()

	// First try to get the combined credentials secret
	projectID := "microcloud-448817" // GCP project ID
	secretName := fmt.Sprintf("projects/%s/secrets/db_credentials/versions/latest", projectID)
	resp, err := client.AccessSecretVersion(ctx, &secretspb.AccessSecretVersionRequest{Name: secretName})
	if err == nil {
		credentials := struct {
			User     string `json:"user"`
			Password string `json:"password"`
		}{}
		if err := json.Unmarshal(resp.Payload.Data, &credentials); err == nil {
			// We only get username and password from Secret Manager
			// The DB_HOST is set by setup.sh or from the .env file
			return credentials.User, credentials.Password, nil
		}
	}
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
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func initDB() (*sql.DB, error) {
	// Try to fetch secrets from GCP Secret Manager, otherwise use .env file
	log.Println("Connecting to the database...")
	user, password, err := getDBCredentials()
	if err != nil {
		return nil, fmt.Errorf("failed to get DB credentials: %w", err)
	}
	host := os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/dr_demo?parseTime=true", user, password, host)
	return sql.Open("mysql", dsn)
}

func getDBCredentials() (string, string, error) {
	ctx := context.Background()
	client, err := secretmanager.NewClient(ctx)
	if err == nil {
		defer client.Close()

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
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func initDB() (*sql.DB, error) {
	// Try to fetch secrets from GCP Secret Manager, otherwise use .env file
	log.Println("Connecting to the database...")
	user, password, err := getDBCredentials()
	if err != nil {
		return nil, fmt.Errorf("failed to get DB credentials: %w", err)
	}
	host := os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s:3306)/dr_demo?parseTime=true", user, password, host)
	return sql.Open("mysql", dsn)
}

func getDBCredentials() (string, string, error) {
	ctx := context.Background()
	client, err := secretmanager.NewClient(ctx)
	if err == nil {
		defer client.Close()

		// First try to get the combined credentials secret
		projectID := "microcloud-448817" // GCP project ID
		secretName := fmt.Sprintf("projects/%s/secrets/db_credentials/versions/latest", projectID)
		resp, err := client.AccessSecretVersion(ctx, &secretspb.AccessSecretVersionRequest{Name: secretName})
		if err == nil {
			credentials := struct {
				User     string `json:"user"`
				Password string `json:"password"`
				Host     string `json:"host"`
			}{}
			if err := json.Unmarshal(resp.Payload.Data, &credentials); err == nil {
				// If we got the host from the secret, set it in the environment
				if credentials.Host != "" {
					os.Setenv("DB_HOST", credentials.Host)
				}
				return credentials.User, credentials.Password, nil
			}
		}

	}

	// Fallback to environment variables
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	if user == "" || password == "" {
		return "", "", fmt.Errorf("missing database credentials")
	}
	return user, password, nil
}

func writeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Invalid request method", http.StatusMethodNotAllowed)
		return
	}

	var request struct {
		Data string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if request.Data == "" {
		http.Error(w, "Missing data", http.StatusBadRequest)
		return
	}

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
	rows, err := db.Query("SELECT data FROM records")
	if err != nil {
		http.Error(w, "Failed to retrieve data", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var data []string
	for rows.Next() {
		var record string
		if err := rows.Scan(&record); err == nil {
			data = append(data, record)
		}
	}

	// Read from file
	fileData, err := os.ReadFile("data_backup.txt")
	if err != nil {
		fileData = []byte("No file data available")
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"database": data,
		"file":     string(fileData),
	})
}

func webHandler(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "web.html")
}
