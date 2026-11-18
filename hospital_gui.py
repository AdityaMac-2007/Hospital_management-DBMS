"""Hospital Management GUI (Tkinter + MySQL).
Setup:  pip install mysql-connector-python
        mysql -u root -p < hospital_management.sql     (creates hospital_db)
Run:    python hospital_gui.py
"""
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import mysql.connector
from mysql.connector import Error

HOST, USER, DATABASE = "localhost", "root", "hospital_db"
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

# "id - name" lists used by drop-downs
PATIENTS = "SELECT patient_id, CONCAT(first_name,' ',IFNULL(last_name,'')) FROM patient"
DOCTORS = "SELECT doctor_id, CONCAT(doc_name,' (',specialization,')') FROM doctor"
DEPTS = "SELECT dept_id, dept_name FROM department"
FREE_ROOMS = ("SELECT r.room_id, CONCAT(r.room_no,' ',rc.category_name) FROM room r "
              "JOIN room_category rc ON rc.category_id=r.category_id WHERE r.status='Available'")


class DB:
    def __init__(self, **cfg):
        self.conn = mysql.connector.connect(**cfg)

    def run(self, sql, params=()):
        cur = self.conn.cursor()
        try:
            cur.execute(sql, params)
            if cur.description:
                return [d[0] for d in cur.description], cur.fetchall()
            self.conn.commit()
            return [], []
        except Error:
            self.conn.rollback()
            raise
        finally:
            cur.close()

    def call(self, name, args):
        cur = self.conn.cursor()
        try:
            cur.callproc(name, args)
            self.conn.commit()
        except Error:
            self.conn.rollback()
            raise
        finally:
            cur.close()


def guard(fn):
    def wrapper(*a):
        try:
            fn(*a)
        except Error as e:
            msg = "That record / time slot already exists." if getattr(e, "errno", 0) == 1062 else str(e)
            messagebox.showerror("Database error", msg)
        except ValueError as e:
            messagebox.showwarning("Check input", str(e))
    return wrapper


def choices(db, q):
    return [f"{a} - {b}" for a, b in db.run(q)[1]]


class Grid(ttk.Frame):
    def __init__(self, parent, height=10):
        super().__init__(parent)
        self.tree = ttk.Treeview(self, show="headings", height=height)
        sb = ttk.Scrollbar(self, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")

    def load(self, cols, rows):
        self.tree.delete(*self.tree.get_children())
        self.tree["columns"] = cols
        for c in cols:
            self.tree.heading(c, text=c)
            self.tree.column(c, width=120, anchor="w")
        for r in rows:
            self.tree.insert("", "end", values=["" if v is None else str(v) for v in r])

    def selected(self):
        sel = self.tree.selection()
        if not sel:
            raise ValueError("Select a row first.")
        return dict(zip(self.tree["columns"], self.tree.item(sel[0])["values"]))


class FormTab(ttk.Frame):
    """Form fields + button bar + result grid."""

    def __init__(self, nb, db, fields):
        super().__init__(nb)
        self.db, self.vars, self.fk = db, {}, set()
        form = ttk.Frame(self)
        form.pack(fill="x", padx=8, pady=6)
        for i, (label, col, kind) in enumerate(fields):
            r, c = divmod(i, 3)
            ttk.Label(form, text=label).grid(row=r, column=c * 2, sticky="e", padx=4, pady=3)
            v = self.vars[col] = tk.StringVar()
            if kind is None:
                w = ttk.Entry(form, textvariable=v, width=24)
            elif isinstance(kind, list):
                w = ttk.Combobox(form, textvariable=v, values=kind, width=22, state="readonly")
            else:  # SQL -> "id - name" drop-down, refreshed every time it opens
                self.fk.add(col)
                w = ttk.Combobox(form, textvariable=v, width=26)
                w.configure(postcommand=lambda w=w, q=kind: w.configure(values=choices(db, q)))
            w.grid(row=r, column=c * 2 + 1, padx=4, pady=3, sticky="w")
        self.bar = ttk.Frame(self)
        self.bar.pack(fill="x", padx=8)
        self.grid_ = Grid(self)
        self.grid_.pack(fill="both", expand=True, padx=8, pady=8)
        self.grid_.tree.bind("<<TreeviewSelect>>", self.on_select)

    def btn(self, text, cmd):
        ttk.Button(self.bar, text=text, command=guard(cmd)).pack(side="left", padx=3, pady=3)

    def get(self, col):
        s = self.vars[col].get().strip()
        if col in self.fk:
            s = s.split(" - ")[0]
        return s or None

    def need(self, *cols):
        vals = [self.get(c) for c in cols]
        if not all(vals):
            raise ValueError("Please fill in all required fields.")
        return vals

    def clear(self):
        for v in self.vars.values():
            v.set("")

    def on_select(self, _):
        try:
            row = self.grid_.selected()
        except ValueError:
            return
        for col, v in self.vars.items():
            if col in row:
                v.set(row[col])

    def refresh(self):
        pass


class CrudTab(FormTab):
    """Generic add / modify / delete / search for one table."""

    def __init__(self, nb, db, table, pk, fields, search_col):
        super().__init__(nb, db, fields)
        self.table, self.pk, self.scol = table, pk, search_col
        self.search = tk.StringVar()
        self.btn("Add", self.add)
        self.btn("Update", self.update)
        self.btn("Delete", self.delete)
        self.btn("Clear", self.clear)
        ttk.Entry(self.bar, textvariable=self.search, width=20).pack(side="left", padx=(20, 3))
        self.btn(f"Search {search_col}", self.refresh)
        self.btn("Show all", lambda: (self.search.set(""), self.refresh()))
        self.refresh()

    def refresh(self):
        s, p = self.search.get().strip(), ()
        sql = f"SELECT * FROM {self.table}"
        if s:
            sql += f" WHERE {self.scol} LIKE %s"
            p = (f"%{s}%",)
        self.grid_.load(*self.db.run(sql + f" ORDER BY {self.pk}", p))

    def add(self):
        cols = list(self.vars)
        self.db.run(f"INSERT INTO {self.table} ({','.join(cols)}) VALUES ({','.join(['%s'] * len(cols))})",
                    [self.get(c) for c in cols])
        self.refresh()
        self.clear()

    def update(self):
        row, cols = self.grid_.selected(), list(self.vars)
        self.db.run(f"UPDATE {self.table} SET {','.join(c + '=%s' for c in cols)} WHERE {self.pk}=%s",
                    [self.get(c) for c in cols] + [row[self.pk]])
        self.refresh()

    def delete(self):
        row = self.grid_.selected()
        if messagebox.askyesno("Confirm", "Delete the selected record?"):
            self.db.run(f"DELETE FROM {self.table} WHERE {self.pk}=%s", (row[self.pk],))
            self.refresh()


class AppointmentTab(FormTab):
    def __init__(self, nb, db):
        super().__init__(nb, db, [("Patient", "patient_id", PATIENTS), ("Doctor", "doctor_id", DOCTORS),
                                  ("Date (YYYY-MM-DD)", "appt_date", None), ("Time (HH:MM)", "appt_time", None)])
        self.btn("Book appointment", self.book)
        self.btn("Cancel selected", self.cancel)
        self.btn("Filter by date", self.refresh)
        self.btn("Show all", lambda: (self.vars["appt_date"].set(""), self.refresh()))
        self.refresh()

    def refresh(self):
        d, p = self.get("appt_date"), ()
        sql = ("SELECT a.appointment_id, CONCAT(p.first_name,' ',IFNULL(p.last_name,'')) AS patient, "
               "d.doc_name AS doctor, a.appt_date, a.appt_time, a.status FROM appointment a "
               "JOIN patient p ON p.patient_id=a.patient_id JOIN doctor d ON d.doctor_id=a.doctor_id")
        if d:
            sql += " WHERE a.appt_date=%s"
            p = (d,)
        self.grid_.load(*self.db.run(sql + " ORDER BY a.appt_date, a.appt_time", p))

    def book(self):
        pat, doc, date, time = self.need("patient_id", "doctor_id", "appt_date", "appt_time")
        ok = self.db.run("SELECT 1 FROM doctor_schedule WHERE doctor_id=%s AND day_of_week=DAYNAME(%s) "
                         "AND %s BETWEEN start_time AND end_time", (doc, date, time))[1]
        if not ok:
            raise ValueError("Doctor is not available at that day/time. Check the Search tab.")
        self.db.run("INSERT INTO appointment(patient_id,doctor_id,appt_date,appt_time) VALUES(%s,%s,%s,%s)",
                    (pat, doc, date, time))
        self.refresh()
        messagebox.showinfo("Booked", "Appointment booked.")

    def cancel(self):
        row = self.grid_.selected()
        self.db.run("UPDATE appointment SET status='Cancelled' WHERE appointment_id=%s", (row["appointment_id"],))
        self.refresh()


class AdmissionTab(FormTab):
    def __init__(self, nb, db):
        super().__init__(nb, db, [("Patient", "patient_id", PATIENTS), ("Doctor", "doctor_id", DOCTORS),
                                  ("Room (available)", "room_id", FREE_ROOMS), ("Reason", "reason", None)])
        self.btn("Admit patient", self.admit)
        self.btn("Discharge selected", self.discharge)
        self.btn("Refresh", self.refresh)
        self.refresh()

    def refresh(self):
        self.grid_.load(*self.db.run(
            "SELECT a.admission_id, CONCAT(p.first_name,' ',IFNULL(p.last_name,'')) AS patient, d.doc_name AS doctor, "
            "r.room_no, rc.category_name, a.admit_date, a.discharge_date FROM admission a "
            "JOIN patient p ON p.patient_id=a.patient_id JOIN doctor d ON d.doctor_id=a.doctor_id "
            "JOIN room r ON r.room_id=a.room_id JOIN room_category rc ON rc.category_id=r.category_id "
            "ORDER BY a.admission_id DESC"))

    def admit(self):
        pat, doc, room = self.need("patient_id", "doctor_id", "room_id")
        self.db.run("INSERT INTO admission(patient_id,doctor_id,room_id,admit_date,reason) "
                    "VALUES(%s,%s,%s,CURDATE(),%s)", (pat, doc, room, self.get("reason")))
        self.refresh()

    def discharge(self):
        row = self.grid_.selected()
        self.db.run("UPDATE admission SET discharge_date=CURDATE() WHERE admission_id=%s AND discharge_date IS NULL",
                    (row["admission_id"],))
        self.refresh()


class SearchTab(ttk.Frame):
    def __init__(self, nb, db):
        super().__init__(nb)
        self.db = db
        self.spec, self.day, self.test = tk.StringVar(), tk.StringVar(value="Any"), tk.StringVar()
        bar = ttk.Frame(self)
        bar.pack(fill="x", padx=8, pady=8)
        ttk.Label(bar, text="Specialisation").pack(side="left")
        ttk.Entry(bar, textvariable=self.spec, width=16).pack(side="left", padx=4)
        ttk.Label(bar, text="Day").pack(side="left")
        ttk.Combobox(bar, textvariable=self.day, values=["Any"] + DAYS, width=11, state="readonly").pack(side="left", padx=4)
        ttk.Button(bar, text="Find doctors", command=guard(self.doctors)).pack(side="left", padx=4)
        ttk.Label(bar, text="Test").pack(side="left", padx=(16, 0))
        ttk.Entry(bar, textvariable=self.test, width=16).pack(side="left", padx=4)
        ttk.Button(bar, text="Test charges", command=guard(self.tests)).pack(side="left", padx=4)
        ttk.Button(bar, text="Room / ICU / OT charges", command=guard(self.rooms)).pack(side="left", padx=12)
        self.grid_ = Grid(self, 18)
        self.grid_.pack(fill="both", expand=True, padx=8, pady=8)

    def doctors(self):
        sql = ("SELECT doc_name, specialization, consultation_fee, day_of_week, start_time, end_time "
               "FROM v_doctor_availability WHERE specialization LIKE %s")
        p = [f"%{self.spec.get().strip()}%"]
        if self.day.get() != "Any":
            sql += " AND day_of_week=%s"
            p.append(self.day.get())
        self.grid_.load(*self.db.run(sql + " ORDER BY doc_name", p))

    def tests(self):
        self.grid_.load(*self.db.run("SELECT test_name, charge FROM diagnostic_test WHERE test_name LIKE %s "
                                     "ORDER BY charge", (f"%{self.test.get().strip()}%",)))

    def rooms(self):
        self.grid_.load(*self.db.run("SELECT * FROM v_room_charges ORDER BY charge"))


class BillingTab(ttk.Frame):
    def __init__(self, nb, db):
        super().__init__(nb)
        self.db = db
        self.pat, self.adm, self.amt = tk.StringVar(), tk.StringVar(), tk.StringVar()
        top = ttk.Frame(self)
        top.pack(fill="x", padx=8, pady=6)
        ttk.Label(top, text="Patient").pack(side="left")
        cb = ttk.Combobox(top, textvariable=self.pat, width=28)
        cb.configure(postcommand=lambda: cb.configure(values=choices(db, PATIENTS)))
        cb.pack(side="left", padx=4)
        ttk.Label(top, text="Admission ID (blank = out-patient)").pack(side="left", padx=(10, 0))
        ttk.Entry(top, textvariable=self.adm, width=8).pack(side="left", padx=4)
        ttk.Button(top, text="Generate bill", command=guard(self.generate)).pack(side="left", padx=8)
        self.bills = Grid(self, 8)
        self.bills.pack(fill="both", expand=True, padx=8, pady=4)
        self.bills.tree.bind("<<TreeviewSelect>>", lambda e: guard(self.show_items)())
        self.items = Grid(self, 8)
        self.items.pack(fill="both", expand=True, padx=8, pady=4)
        pay = ttk.Frame(self)
        pay.pack(fill="x", padx=8, pady=6)
        ttk.Label(pay, text="Payment amount").pack(side="left")
        ttk.Entry(pay, textvariable=self.amt, width=12).pack(side="left", padx=4)
        ttk.Button(pay, text="Record payment", command=guard(self.pay)).pack(side="left", padx=4)
        ttk.Button(pay, text="Refresh", command=guard(self.refresh)).pack(side="left", padx=4)
        self.refresh()

    def refresh(self):
        self.bills.load(*self.db.run("SELECT * FROM v_bill_summary ORDER BY bill_id DESC"))

    def generate(self):
        if not self.pat.get().strip():
            raise ValueError("Choose a patient.")
        pid = int(self.pat.get().split(" - ")[0])
        adm = int(self.adm.get()) if self.adm.get().strip() else None
        self.db.call("generate_bill", (pid, adm))
        self.refresh()

    def show_items(self):
        try:
            bid = self.bills.selected()["bill_id"]
        except ValueError:
            return
        self.items.load(*self.db.run("SELECT item_type, description, amount FROM bill_item WHERE bill_id=%s", (bid,)))

    def pay(self):
        bid = self.bills.selected()["bill_id"]
        self.db.call("pay_bill", (int(bid), float(self.amt.get())))
        self.refresh()


def main():
    root = tk.Tk()
    root.withdraw()
    pw = simpledialog.askstring("MySQL login", f"Password for MySQL user '{USER}':", show="*")
    if pw is None:
        return
    try:
        db = DB(host=HOST, user=USER, password=pw, database=DATABASE)
    except Error as e:
        messagebox.showerror("Connection failed", str(e))
        return
    root.deiconify()
    root.title("Hospital Management System")
    root.geometry("1150x680")
    nb = ttk.Notebook(root)
    nb.pack(fill="both", expand=True)
    nb.add(CrudTab(nb, db, "patient", "patient_id", [
        ("First name", "first_name", None), ("Last name", "last_name", None), ("Gender", "gender", ["M", "F", "O"]),
        ("DOB (YYYY-MM-DD)", "dob", None), ("Phone", "phone", None), ("Address", "address", None),
        ("Blood group", "blood_group", None)], "first_name"), text="Patients")
    nb.add(CrudTab(nb, db, "doctor", "doctor_id", [
        ("Name", "doc_name", None), ("Specialization", "specialization", None), ("Phone", "phone", None),
        ("Email", "email", None), ("Consultation fee", "consultation_fee", None), ("Department", "dept_id", DEPTS)],
        "specialization"), text="Doctors")
    nb.add(AppointmentTab(nb, db), text="Appointments")
    nb.add(AdmissionTab(nb, db), text="Admissions")
    nb.add(CrudTab(nb, db, "treatment", "treatment_id", [
        ("Patient", "patient_id", PATIENTS), ("Doctor", "doctor_id", DOCTORS),
        ("Admission ID (blank = OPD)", "admission_id", None), ("Diagnosis", "diagnosis", None),
        ("Treatment", "treatment_desc", None), ("Date (YYYY-MM-DD)", "treatment_date", None),
        ("Charge", "charge", None)], "diagnosis"), text="Treatments")
    nb.add(CrudTab(nb, db, "diagnostic_test", "test_id", [
        ("Test name", "test_name", None), ("Charge", "charge", None)], "test_name"), text="Diagnostic tests")
    nb.add(SearchTab(nb, db), text="Search")
    nb.add(BillingTab(nb, db), text="Billing")
    root.mainloop()


if __name__ == "__main__":
    main()
