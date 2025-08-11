# /etc/nginx/sites-available/168port.168cap.com
server {
    listen 80;
    server_name 168port.168cap.com;

    location / {
        proxy_pass http://localhost:8012;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}